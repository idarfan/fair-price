# frozen_string_literal: true

class Api::V1::TrackedTickersController < Api::V1::BaseController
  # tracked_tickers 是共用的蒐集設定，不是個人清單：systemd 的
  # options-collector.timer 與 options-intraday.timer 直接讀
  # `SELECT ... FROM tracked_tickers WHERE active = true`，蒐集結果
  # option_snapshots（79 萬列）綁的是 tracked_ticker_id 而非 symbol，
  # 所以沒辦法像觀察清單那樣簡單地分給每個使用者。
  #
  # 折衷做法：讀取所有人都可以，但**只有 admin 能改動**，避免其他帳號
  # 刪掉代號時連帶 dependent: :destroy 掉整段歷史快照。
  before_action :require_admin!, only: %i[create update destroy collect]

  def index
    render json: TrackedTickerSerializer.list(TrackedTicker.order(:symbol))
  end

  def create
    symbol = params[:symbol].to_s.upcase.strip
    return render json: { error: "symbol 必填" }, status: :unprocessable_entity if symbol.blank?

    ticker = TrackedTicker.find_or_initialize_by(symbol: symbol)
    ticker.active = true

    if ticker.save
      render json: TrackedTickerSerializer.one(ticker), status: ticker.previously_new_record? ? :created : :ok
    else
      render json: { error: ticker.errors.full_messages.join(", ") }, status: :unprocessable_entity
    end
  end

  def update
    ticker = TrackedTicker.find(params[:id])
    if ticker.update(ticker_params)
      render json: TrackedTickerSerializer.one(ticker)
    else
      render json: { error: ticker.errors.full_messages.join(", ") }, status: :unprocessable_entity
    end
  end

  def destroy
    TrackedTicker.find(params[:id]).destroy!
    head :no_content
  end

  # POST /api/v1/tracked_tickers/:id/collect
  # 排入背景 job 執行 Python 蒐集器，立刻回 job_id 讓前端輪詢 #collect_status。
  # （過去是在 request 內同步跑子行程且無 timeout，會把 Puma thread 卡死。）
  def collect
    ticker = TrackedTicker.find(params[:id])
    job_id = SecureRandom.hex(8)

    Rails.cache.write(
      CollectOptionSnapshotsJob.cache_key(job_id),
      { status: "pending", symbol: ticker.symbol },
      expires_in: CollectOptionSnapshotsJob::CACHE_TTL
    )
    CollectOptionSnapshotsJob.perform_later(ticker.id, job_id)

    render json: { job_id: job_id, symbol: ticker.symbol, status: "pending" }, status: :accepted
  end

  # GET /api/v1/tracked_tickers/collect_status?job_id=...
  def collect_status
    job_id = params[:job_id].to_s.gsub(/[^a-f0-9]/, "")
    return render json: { status: "error", errors: [ "missing job_id" ] }, status: :unprocessable_entity if job_id.blank?

    cached = Rails.cache.read(CollectOptionSnapshotsJob.cache_key(job_id))
    return render json: { status: "expired", errors: [ "工作已過期，請重試" ] } if cached.nil?

    render json: cached
  end

  private

  def require_admin!
    return if current_user&.admin?

    render json: { error: "admin_required", message: "追蹤代號清單為共用設定，僅管理員可修改" },
           status: :forbidden
  end

  def ticker_params
    params.require(:tracked_ticker).permit(:active)
  end
end
