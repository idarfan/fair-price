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

    // ── 歐歐每日盤前報告（週一至五 13:00 UTC = 美東夏令 09:00 EDT / 冬令 08:00 EST）
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
      cron_restart: '0 13 * * 1-5',
      autorestart: false,   // 執行完即停，不自動重啟
      watch: false,
    },
  ],
}
