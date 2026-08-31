# frozen_string_literal: true

# LEAPS 排行表的欄位順序是**全站共用設定**（所有人看到同一個順序），
# 不是個人偏好，所以比照 TrackedTickersController 的做法：讀取隨頁面渲染，
# 寫入只有 admin 可以。前端的 data-col-reorder 只是「要不要掛拖曳」的提示，
# 真正的權限在這裡，把屬性改回來也繞不過。
class Api::V1::LeapsColumnOrdersController < Api::V1::BaseController
  before_action :require_admin!

  def update
    keys = Array(params[:column_keys]).map(&:to_s)

    unless permutation_of_known_columns?(keys)
      return render json: {
        error: "invalid_column_keys",
        message: "欄位順序必須剛好包含全部欄位各一次"
      }, status: :unprocessable_entity
    end

    ColumnOrder.replace!(ColumnOrder::LEAPS_RANKING, keys, user: current_user)
    render json: { column_keys: keys }
  end

  private

  # 只接受「恰好是已知欄位的一種排列」——不多、不少、不重複。
  # 允許缺漏的話，前端一個 bug 就會把欄位永久刪掉；
  # LeapsTableColumns.sanitize 那層補正是給「程式加減欄位」用的，不是給寫入路徑放水。
  def permutation_of_known_columns?(keys)
    keys.uniq.size == keys.size &&
      keys.sort == LeapsTableColumns::DEFAULT_KEYS.sort
  end

  def require_admin!
    return if current_user&.admin?

    render json: {
      error: "admin_required",
      message: "欄位順序為全站共用設定，僅管理員可修改"
    }, status: :forbidden
  end
end
