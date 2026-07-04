import { useEffect } from 'react'
import './index.css'
import { useStore } from './store'
import { Sidebar } from './components/Sidebar'
import { Dashboard } from './views/Dashboard'
import { Income } from './views/Income'
import { Expenses } from './views/Expenses'
import { CashFlow } from './views/CashFlow'
import { julyData } from './data/july2025'

export default function App() {
  const { view, importIncome } = useStore()

  useEffect(() => {
    // Seed July 2025 historical data once (importIncome deduplicates by id)
    importIncome(julyData)
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
