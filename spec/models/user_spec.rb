require "rails_helper"

RSpec.describe User, type: :model do
  # ── Validations ─────────────────────────────────────────────────────────────

  describe "validations" do
    it "is valid with all required attributes" do
      expect(build(:user)).to be_valid
    end

    it "is invalid without email" do
      expect(build(:user, email: nil)).not_to be_valid
    end

    it "is invalid with a duplicate email" do
      create(:user, email: "dup@example.com")
      expect(build(:user, email: "dup@example.com")).not_to be_valid
    end

    it "is invalid without google_uid" do
      expect(build(:user, google_uid: nil)).not_to be_valid
    end

    it "is invalid with a duplicate google_uid" do
      create(:user, google_uid: "dup-uid")
      expect(build(:user, google_uid: "dup-uid")).not_to be_valid
    end
  end

  # ── Enum ─────────────────────────────────────────────────────────────────────

  describe "status enum" do
    it "defaults to pending" do
      expect(create(:user).status).to eq("pending")
    end

    it "accepts enabled and disabled" do
      expect(build(:user, status: :enabled)).to be_valid
      expect(build(:user, status: :disabled)).to be_valid
    end
  end

  # ── Encryption ───────────────────────────────────────────────────────────────

  describe "encrypted attributes" do
    it "round-trips totp_secret through the database" do
      user = create(:user, totp_secret: "top-secret-value")
      reloaded = described_class.find(user.id)
      expect(reloaded.totp_secret).to eq("top-secret-value")
    end

    it "does not store totp_secret as plaintext" do
      user = create(:user, totp_secret: "top-secret-value")
      raw = ActiveRecord::Base.connection.select_value(
        "SELECT totp_secret FROM users WHERE id = #{user.id}"
      )
      expect(raw).not_to include("top-secret-value")
    end

    it "round-trips backup_codes through the database" do
      user = create(:user, backup_codes: "code1,code2")
      reloaded = described_class.find(user.id)
      expect(reloaded.backup_codes).to eq("code1,code2")
    end
  end

  # ── Associations ─────────────────────────────────────────────────────────────

  describe "associations" do
    it "destroys dependent user_activities" do
      user = create(:user)
      create(:user_activity, user: user)
      expect { user.destroy! }.to change(UserActivity, :count).by(-1)
    end
  end
end
