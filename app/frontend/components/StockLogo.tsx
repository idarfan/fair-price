import { useState, useEffect } from 'react'

interface Props {
  symbol: string
  size?:  'sm' | 'md'
}

const SIZE_CLASS = {
  sm: 'w-7 h-7',
  md: 'w-9 h-9',
} as const

export default function StockLogo({ symbol, size = 'sm' }: Props) {
  const [src, setSrc] = useState(
    `https://assets.parqet.com/logos/symbol/${symbol}?format=jpg`
  )
  const [failed, setFailed] = useState(false)

  // symbol 變更時重設圖片來源
  useEffect(() => {
    setSrc(`https://assets.parqet.com/logos/symbol/${symbol}?format=jpg`)
    setFailed(false)
  }, [symbol])

  function handleError() {
    if (!src.includes('finnhub')) {
      setSrc(`https://static2.finnhub.io/file/publicdatany/finnhubimage/stock_logo/${symbol}.png`)
    } else {
      setFailed(true)
    }
  }

  const cls = SIZE_CLASS[size]

  if (failed) {
    return (
      <span
        className={`${cls} rounded-full bg-gray-600 text-white font-bold flex items-center justify-center flex-shrink-0`}
        style={{ fontSize: size === 'sm' ? '8px' : '10px' }}
      >
        {symbol.slice(0, 2)}
      </span>
    )
  }

  return (
    <img
      src={src}
      alt={symbol}
      onError={handleError}
      className={`${cls} rounded-full object-contain border border-gray-600 bg-white flex-shrink-0`}
    />
  )
}
