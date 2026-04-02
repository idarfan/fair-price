import { useState } from 'react'
import { CalculatorTab } from './components/CalculatorTab'
import { PositionListTab } from './components/PositionListTab'

type Tab = 'calculator' | 'positions'

export function MarginApp() {
  const [activeTab, setActiveTab] = useState<Tab>('calculator')

  return (
    <div className="flex flex-col h-full bg-gray-900 text-white">
      {/* Tab bar */}
      <div className="flex border-b border-gray-700 px-4 pt-3">
        {([
          { id: 'calculator', label: '📊 融資試算器' },
          { id: 'positions',  label: '📋 融資持股清單' },
        ] as { id: Tab; label: string }[]).map(tab => (
          <button
            key={tab.id}
            onClick={() => setActiveTab(tab.id)}
            className={`px-4 py-2 text-sm font-medium border-b-2 transition-colors mr-2
              ${activeTab === tab.id
                ? 'border-blue-500 text-blue-400'
                : 'border-transparent text-gray-400 hover:text-gray-200'}`}
          >
            {tab.label}
          </button>
        ))}
      </div>

      {/* Content */}
      <div className="flex-1 overflow-y-auto p-4">
        {activeTab === 'calculator' ? <CalculatorTab /> : <PositionListTab />}
      </div>
    </div>
  )
}
