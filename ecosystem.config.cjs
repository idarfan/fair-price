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
  ],
}
