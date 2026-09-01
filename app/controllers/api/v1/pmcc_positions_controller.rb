# frozen_string_literal: true

# pmcc-tracker Phase 5：部位的寫入操作。
#
# **一律從 current_user 出發**（比照 Api::V1::MarginPositionsController）：
# 別人的 id 直接 RecordNotFound，不是「查得到但不能改」。只加 user_id 欄位
# 而查詢不 scope 等於白加。
#
# 金額公式集中在 PmccPnlService 的 class method，這裡不重寫一份——
# 表單各寫一份是帳本對不起來的起點。
class Api::V1::PmccPositionsController < Api::V1::BaseController
  before_action :load_position, except: :create

  def create
    position = current_user.pmcc_positions.new(position_params)

    if position.save
      render json: serialize(position), status: :created
    else
      render json: { error: position.errors.full_messages.join(", ") },
             status: :unprocessable_entity
    end
  end

  def destroy
    @position.destroy!
    head :no_content
  end

  # 滾倉：買回目前短腳、賣出新短腳，一筆 short_closed 事件。
  # 整段包在 transaction 裡——中途失敗會留下「舊腳關了、新腳沒開」的
  # 破碎狀態，帳本從此對不起來。
  def roll
    leg = @position.open_short_leg
    return render_no_open_leg if leg.blank?

    close_cost = decimal_param(:close_cost)
    return render_missing("close_cost") if close_cost.nil?

    new_leg = nil
    ActiveRecord::Base.transaction do
      record_close_event(leg, "short_closed", close_cost)
      leg.update!(status: "rolled", close_cost: close_cost, closed_at: Time.current)

      new_leg = @position.short_legs.create!(
        contracts:         params[:contracts].presence&.to_i || leg.contracts,
        short_strike:      decimal_param(:new_strike),
        short_expiration:  params[:new_expiration],
        premium_collected: decimal_param(:new_premium),
        opened_at:         Time.current,
        status:            "open"
      )
      leg.update!(rolled_to: new_leg)
    end

    render json: serialize(@position.reload).merge(new_short_leg_id: new_leg.id)
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.join(", ") }, status: :unprocessable_entity
  end

  # 到期歸零：沒有買回成本，收租全數落袋
  def expire
    close_leg_with("expired_worthless", "short_expired", 0)
  end

  # 被指派：只記短腳自己的現金流。長腳因此被行權/平倉要另外送 close，
  # 把長腳的估算損失塞進這筆會讓已實現帳本不再可稽核。
  def assign
    cost = decimal_param(:close_cost) || 0
    close_leg_with("assigned", "short_assigned", cost)
  end

  # 整個部位平倉：兩腳一起（Sell to Close 長腳 + Buy to Close 短腳）。
  # 這是結束部位的預設路徑，履約交割只在無法市場平倉時才用。
  def close
    sell_price = decimal_param(:long_sell_price)
    return render_missing("long_sell_price") if sell_price.nil?

    ActiveRecord::Base.transaction do
      leg = @position.open_short_leg
      if leg.present?
        cost = decimal_param(:short_close_cost) || 0
        record_close_event(leg, "short_closed", cost)
        leg.update!(status: "expired_worthless", close_cost: cost, closed_at: Time.current)
      end

      @position.pnl_events.create!(
        event_type:   "long_closed",
        realized_pnl: PmccPnlService.long_closed_pnl(@position, sell_price: sell_price, fees: fees_param),
        fees:         fees_param,
        occurred_at:  Time.current,
        note:         params[:note].presence
      )
      @position.update!(status: "closed", closed_at: Time.current)
    end

    render json: serialize(@position.reload)
  end

  private

  def close_leg_with(leg_status, event_type, close_cost)
    leg = @position.open_short_leg
    return render_no_open_leg if leg.blank?

    ActiveRecord::Base.transaction do
      record_close_event(leg, event_type, close_cost)
      leg.update!(status: leg_status, close_cost: close_cost, closed_at: Time.current)
    end

    render json: serialize(@position.reload)
  end

  def record_close_event(leg, event_type, close_cost)
    amount = case event_type
    when "short_expired"  then PmccPnlService.short_expired_pnl(leg, fees: fees_param)
    when "short_assigned" then PmccPnlService.short_assigned_pnl(leg, close_cost: close_cost, fees: fees_param)
    else                       PmccPnlService.short_closed_pnl(leg, close_cost: close_cost, fees: fees_param)
    end

    @position.pnl_events.create!(
      event_type:     event_type,
      realized_pnl:   amount,
      fees:           fees_param,
      occurred_at:    Time.current,
      note:           params[:note].presence,
      # pmcc_leg_quotes 是覆蓋式快照，事後查不到當時值，要能回溯就得在這裡留存
      quote_snapshot: { close_cost: close_cost.to_f, premium_collected: leg.premium_collected.to_f,
                        contracts: leg.contracts }
    )
  end

  # 別人的 id 直接 RecordNotFound（BaseController 會轉成 404）
  def load_position
    @position = current_user.pmcc_positions.find(params[:id])
  end

  def position_params
    params.permit(:ticker, :long_contracts, :long_strike, :long_expiration,
                  :long_entry_cost, :long_entry_date)
  end

  def decimal_param(key)
    params[key].presence&.to_d
  end

  def fees_param
    decimal_param(:fees) || 0
  end

  def render_no_open_leg
    render json: { error: "目前沒有未平倉的短腳" }, status: :unprocessable_entity
  end

  def render_missing(field)
    render json: { error: "#{field} 必填" }, status: :unprocessable_entity
  end

  def serialize(position)
    {
      id:       position.id,
      ticker:   position.ticker,
      status:   position.status,
      realized: position.realized_pnl.to_f,
      open_short_leg_id: position.open_short_leg&.id
    }
  end
end
