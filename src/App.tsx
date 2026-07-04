import { useEffect } from 'react'
import './index.css'
import { useStore } from './store'
import { Sidebar } from './components/Sidebar'
import { Dashboard } from './views/Dashboard'
import { Income } from './views/Income'
import { Expenses } from './views/Expenses'
import { CashFlow } from './views/CashFlow'
import { julyData } from './data/july2025'
import { augData } from './data/aug2025'
import { sepData } from './data/sep2025'
import { octData } from './data/oct2025'
import { novData } from './data/nov2025'
import { decData } from './data/dec2025'
import { janData } from './data/jan2026'
import { febData } from './data/feb2026'
import { marData } from './data/mar2026'
import { aprData } from './data/apr2026'

export default function App() {
  const { view, importIncome } = useStore()

  useEffect(() => {
    ;[julyData, augData, sepData, octData, novData, decData, janData, febData, marData, aprData].forEach(importIncome)
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  return (
    <div className="flex h-screen bg-slate-50 overflow-hidden">
      <Sidebar />
      <main className="flex-1 overflow-y-auto">
        {view === 'dashboard' && <Dashboard />}
        {view === 'income' && <Income />}
        {view === 'expenses' && <Expenses />}
        {view === 'cashflow' && <CashFlow />}
      </main>
    </div>
  )
}
