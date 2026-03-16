# CLAUDE.md — FairPrice / Daily Momentum

This file provides guidance to Claude Code when working with this repository.

## Session Start

- **Always review `tasks/lessons.md` at session start** for relevant project patterns and past corrections.

## Work Habits

### Plan Mode Default
- Enter plan mode for ANY non-trivial task (3+ steps or architectural decisions)
- If something goes sideways, STOP and re-plan immediately — don't keep pushing
- Use plan mode for verification steps, not just building
- Write detailed specs upfront to reduce ambiguity

### Subagent Strategy
- Use subagents liberally to keep main context window clean
- Offload research, exploration, and parallel analysis to subagents
- For complex problems, throw more compute at it via subagents
- One task per subagent for focused execution

### Self-Improvement Loop
- After ANY correction from the user: update `tasks/lessons.md` with the pattern
- Write rules for yourself that prevent the same mistake
- Ruthlessly iterate on these lessons until mistake rate drops

### Verification Before Done
- Never mark a task complete without proving it works
- Diff behavior between main and your changes when relevant
- Ask yourself: "Would a staff engineer approve this?"
- Run tests, check logs, demonstrate correctness

### Demand Elegance (Balanced)
- For non-trivial changes: pause and ask "is there a more elegant way?"
- If a fix feels hacky: "Knowing everything I know now, implement the elegant solution"
- Skip this for simple, obvious fixes — don't over-engineer

### Autonomous Bug Fixing
- When given a bug report: just fix it. Don't ask for hand-holding
- Point at logs, errors, failing tests — then resolve them
- Zero context switching required from the user

## Task Management

1. **Plan First**: Write plan to `tasks/todo.md` with checkable items
2. **Verify Plan**: Check in before starting implementation
3. **Track Progress**: Mark items complete as you go
4. **Explain Changes**: High-level summary at each step
5. **Document Results**: Add review section to `tasks/todo.md`
6. **Capture Lessons**: Update `tasks/lessons.md` after corrections

## Core Principles

- **Simplicity First**: Make every change as simple as possible. Impact minimal code.
- **No Laziness**: Find root causes. No temporary fixes. Senior developer standards.

---

## Commands

```bash
# Start / manage the server (port 3003)
systemctl --user restart fairprice
systemctl --user status  fairprice
journalctl --user -u fairprice -n 30

# Lint (auto-fix correctable offenses)
bundle exec rubocop
bundle exec rubocop -a

# Boot check
bundle exec rails runner "puts 'Boot OK'"

# Routes
bundle exec rails routes

# Lookbook component previews (dev only)
open http://localhost:3003/lookbook
```

## Architecture

**No database. No React. No Vite.** This is a pure Phlex + Tailwind CDN app backed by Finnhub HTTP calls.

The app hosts two tools under one process on port 3003:

| Tool | Route | Controller | Namespace |
|------|-------|------------|-----------|
| FairPrice | `/`, `/valuations/:ticker` | `ValuationsController` | `FairValue::` |
| Daily Momentum | `/momentum` | `ReportsController` | `DailyMomentum::` |
| JSON API | `/api/v1/valuations/:ticker` | `Api::V1::ValuationsController` | — |

Both tools share:
- `ApplicationComponent` base class (`app/components/application_component.rb`) — formatting helpers (`fmt_currency`, `fmt_percent`, `fmt_large`, `change_color`, `upside_color`)
- `ApplicationHelper` — momentum risk helpers (`risk_level`, `max_position_note`)
- `FairValue::AppSwitcherComponent` — left sidebar rendered in the main layout
- `app/views/layouts/application.html.erb` — shared layout with navbar + sidebar

## FairPrice data flow

```
ValuationsController#show
  └── StockDataService.fetch(ticker)       → Finnhub /quote, /metric, /profile2, /recommendation
        └── ValuationService.calculate(data, discount_rate)
              → classifies stock type → applies DCF/P-E/PEG/DDM/P-B/EV-EBITDA
```

Stock type classification in `ValuationService` drives which valuation methods are used. To add a new method: write a private method returning `{ method:, value:, note:, formula: }` and add it to the relevant `*_methods` array — the Phlex components render it automatically.

## Daily Momentum data flow

```
ReportsController#index
  └── MomentumReportService#call
        ├── FinnhubService#quote("^VIX")   → vix
        ├── FinnhubService#quote(symbol)×N → stocks  (symbols from config/watchlist.yml)
        ├── FinnhubService#market_news     → news
        └── FinnhubService#earnings_calendar → earnings
```

Edit `config/watchlist.yml` to change tracked symbols — no code change needed.

Market time segment (`:market_hours`, `:pre_market`, `:after_hours`, `:closed`) is derived from ET clock time in `MomentumReportService#time_segment`.

## Adding a new tool to the sidebar

1. Add a route in `config/routes.rb`
2. Create controller + view under the new namespace
3. Add the tool entry to `APP_LINKS` in `app/components/fair_value/app_switcher_component.rb`
