# frozen_string_literal: true

class TrackController < ApplicationController
  skip_forgery_protection

  def page_view
    return head :no_content unless logged_in?

    activity = current_user.user_activities.find_or_initialize_by(
      activity_token: params[:activity_token]
    )
    activity.assign_attributes(
      kind:          :page_view,
      path:          params[:path],
      referrer_path: params[:referrer_path],
      started_at:    activity.started_at || Time.current,
      ended_at:      Time.current,
      duration_ms:   params[:duration_ms]
    )
    unless activity.save
      Rails.logger.warn("[Track#page_view] 寫入失敗：#{activity.errors.full_messages.join(', ')}")
    end
    head :no_content
  end

  def command
    return head :no_content unless logged_in?

    current_user.user_activities.create(
      kind:        :command,
      action_name: params[:action_name],
      metadata:    parsed_metadata,
      started_at:  Time.current
    )
    head :no_content
  end

  private

  def parsed_metadata
    JSON.parse(params[:metadata].to_s)
  rescue JSON::ParserError
    {}
  end
end
