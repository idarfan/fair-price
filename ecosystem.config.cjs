module.exports = {
  apps: [
    {
      name: 'fairprice-rails',
      script: './bin/start-rails.sh',
      cwd: '/home/idarfan/fairprice',
      interpreter: '/bin/bash',
      env: {
        RAILS_ENV: 'development',
        HOME: '/home/idarfan',
        PATH: '/home/idarfan/.rbenv/shims:/home/idarfan/.rbenv/bin:/usr/bin:/bin',
        RBENV_ROOT: '/home/idarfan/.rbenv',
      },
      autorestart: true,
      watch: false,
      max_restarts: 5,
      min_uptime: '10s',   // 10s 內掛掉才算 crash
      restart_delay: 5000, // crash 後等 5s 再重啟
    },
    {
      name: 'fairprice-vite',
      script: 'npm',
      args: 'exec vite -- --mode development',
      cwd: '/home/idarfan/fairprice',
      interpreter: 'none',
      autorestart: true,
      watch: false,
      max_restarts: 5,
      restart_delay: 3000,
    },
    // ── 歐歐 Telegram Bot（長輪詢，回應群組 @OhmyOpenClawPriceBot 個股分析）
    {
      name: 'ouou-telegram-bot',
      script: 'bin/rails',
      args: 'runner "TelegramBotPollingService.new.run"',
      cwd: '/home/idarfan/fairprice',
      interpreter: 'none',
      env: {
        RAILS_ENV: 'development',
        HOME: '/home/idarfan',
        PATH: '/home/idarfan/.rbenv/shims:/home/idarfan/.rbenv/bin:/usr/bin:/bin',
        RBENV_ROOT: '/home/idarfan/.rbenv',
      },
      autorestart: true,
      watch: false,
      max_restarts: 10,
      min_uptime: '10s',
      restart_delay: 5000,
    },

    // ── 歐歐每日盤前報告（迴圈模式，腳本內部判斷週一至五 09:00–09:04 ET）
    {
      name: 'ouou-pre-market',
      script: './bin/ouou-pre-market.sh',
      cwd: '/home/idarfan/fairprice',
      interpreter: '/bin/bash',
      env: {
        RAILS_ENV: 'development',
        HOME: '/home/idarfan',
        PATH: '/home/idarfan/.rbenv/shims:/home/idarfan/.rbenv/bin:/usr/bin:/bin',
        RBENV_ROOT: '/home/idarfan/.rbenv',
      },
      autorestart: true,
      watch: false,
      max_restarts: 10,
      min_uptime: '10s',
      restart_delay: 5000,
    },

    // ── IV 每日 ATM IV 快照（收盤後 16:30 ET = 20:30 UTC）
    // 所有 cron 以 UTC 表達（pm2 daemon 啟動時需設 TZ=UTC）
    {
      name: 'iv-daily-snapshot',
      script: './bin/iv-daily-snapshot.sh',
      cwd: '/home/idarfan/fairprice',
      interpreter: '/bin/bash',
      cron_restart: '30 20 * * 1-5',
      autorestart: false,
      watch: false,
    },

    // ── IV 每日 25-delta Skew 快照（收盤後 16:45 ET = 20:45 UTC）
    {
      name: 'iv-skew-snapshot',
      script: './bin/iv-skew-snapshot.sh',
      cwd: '/home/idarfan/fairprice',
      interpreter: '/bin/bash',
      cron_restart: '45 20 * * 1-5',
      autorestart: false,
      watch: false,
    },

    // ── IV 盤中 30 分鐘 Skew 快照（ET 09:00-16:00 = UTC 13:00-20:00）
    // rake task 內部再過濾非交易時段
    {
      name: 'iv-skew-intraday',
      script: './bin/iv-skew-intraday.sh',
      cwd: '/home/idarfan/fairprice',
      interpreter: '/bin/bash',
      cron_restart: '*/30 13-20 * * 1-5',
      autorestart: false,
      watch: false,
    },
  ],
}
