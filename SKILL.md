---
name: fairprice
description: US stock fair value estimator. Triggered when user inputs a stock ticker followed by context like "fair value", "公允價值", "估值", "合理價", or "FairPrice". Launches the Rails web app and opens the interactive React dashboard for deep valuation analysis.
---

# FairPrice — US Stock Fair Value Rails App

## Architecture

Ruby on Rails backend + React interactive dashboard (`fair_value_analysis.jsx`).
- Backend fetches live data from Yahoo Finance and applies valuation methods
- Frontend renders an interactive fair value analysis dashboard for any stock ticker

## Workflow

### Option A: Launch Web App (recommended)

```bash
cd ~/.openclaw/skills/fairprice
bin/dev
```

Then open `http://localhost:3003` in the browser and enter the stock ticker.

### Option B: Direct API Query

```bash
curl "http://localhost:3003/api/v1/valuations/{TICKER}?discount_rate=10"
```

Returns JSON with full valuation data.

## Setup (first time only)

```bash
cd ~/.openclaw/skills/fairprice

# Generate Rails boilerplate
gem install rails
rails new . --force --skip-active-record --skip-git \
            --skip-action-mailer --skip-action-mailbox \
            --skip-action-text --skip-active-job \
            --skip-active-storage --skip-action-cable --skip-test

# Install dependencies
bundle install
npm install
bundle exec vite install

# Start server
bin/dev
```

## Valuation Methods

Auto-selected based on stock type:

| Type       | Methods |
|------------|---------|
| 一般股     | DCF + P/E + PEG |
| 金融股     | ExcessReturns + P/E + P/B |
| REITs      | DDM + DCF + P/B |
| 公用事業   | DDM + DCF + P/E |
| 虧損成長股 | Revenue Multiple + DCF (conservative) |
| 週期股     | EV/EBITDA + P/B + DCF |

## Notes

- Supports any Yahoo Finance ticker including ADR/foreign stocks (e.g. `2330.TW`)
- Currency conversion handled automatically for ADR stocks
- Exchange rate (USD/TWD) cached for 1 hour
- All output in Traditional Chinese
