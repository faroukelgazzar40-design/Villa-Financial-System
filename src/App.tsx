import './index.css'
import { useStore } from './store'
import { Sidebar } from './components/Sidebar'
import { Dashboard } from './views/Dashboard'
import { Income } from './views/Income'
import { Expenses } from './views/Expenses'
import { CashFlow } from './views/CashFlow'

export default function App() {
  const { view } = useStore()

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
