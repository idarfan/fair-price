# frozen_string_literal: true

class FlightController < ApplicationController
  before_action :load_conversation

  def index
    @pairs = @conversation.message_pairs
  end

  def chat
    message = params[:message].to_s.strip
    return render json: { error: "請輸入問題" }, status: :unprocessable_entity if message.blank?

    history   = @conversation.history_for_api
    reply_md  = FlightChatService.new.call(message, history)
    reply_html = Kramdown::Document.new(reply_md, input: "GFM").to_html

    @conversation.flight_messages.create!(role: "user",      content: message)
    @conversation.flight_messages.create!(role: "assistant", content: reply_md)

    new_index = @conversation.flight_messages.count / 2 - 1
    render json: { reply_html: reply_html, question: message, index: new_index }
  rescue => e
    Rails.logger.error("[FlightController#chat] #{e.class}: #{e.message}")
    render json: { error: "查詢失敗：#{e.message}" }, status: :internal_server_error
  end

  def clear
    # 捨棄舊 token → 下次建立全新對話；舊記錄保留在 DB
    session.delete(:flight_conversation_token)
    redirect_to flight_path
  end

  private

  def load_conversation
    token = session[:flight_conversation_token]
    @conversation = FlightConversation.find_or_create_for_token(token)
    session[:flight_conversation_token] = @conversation.token
  end
end
