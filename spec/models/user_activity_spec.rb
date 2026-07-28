require "rails_helper"

RSpec.describe UserActivity, type: :model do
  describe "validations" do
    it "is valid with all required attributes" do
      expect(build(:user_activity)).to be_valid
    end

    it "is invalid without started_at" do
      expect(build(:user_activity, started_at: nil)).not_to be_valid
    end

    it "is invalid without a user" do
      expect(build(:user_activity, user: nil)).not_to be_valid
    end
  end

  describe "kind enum" do
    it "accepts page_view and command" do
      expect(build(:user_activity, kind: :page_view)).to be_valid
      expect(build(:user_activity, kind: :command)).to be_valid
    end
  end

  describe "associations" do
    it "belongs to a user" do
      activity = create(:user_activity)
      expect(activity.user).to be_a(User)
    end
  end
end
