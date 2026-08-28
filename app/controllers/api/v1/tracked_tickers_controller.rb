# frozen_string_literal: true

class Api::V1::TrackedTickersController < Api::V1::BaseController
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

  def ticker_params
    params.require(:tracked_ticker).permit(:active)
  end
end
