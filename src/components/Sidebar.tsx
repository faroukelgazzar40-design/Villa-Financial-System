import { LayoutDashboard, TrendingUp, TrendingDown, LineChart, Menu, X } from 'lucide-react'
import { useState } from 'react'
import { useStore } from '../store'
import { View } from '../types'

const navItems: { view: View; label: string; icon: React.ReactNode }[] = [
  { view: 'dashboard', label: 'Dashboard', icon: <LayoutDashboard size={20} /> },
  { view: 'income', label: 'Income', icon: <TrendingUp size={20} /> },
  { view: 'expenses', label: 'Expenses', icon: <TrendingDown size={20} /> },
  { view: 'cashflow', label: 'Cash Flow', icon: <LineChart size={20} /> },
]

export function Sidebar() {
  const { view, setView } = useStore()
  const [open, setOpen] = useState(false)

  return (
    <>
      {/* Mobile toggle */}
      <button
        className="fixed top-4 left-4 z-50 md:hidden bg-slate-800 text-white p-2 rounded-lg"
        onClick={() => setOpen(!open)}
      >
        {open ? <X size={20} /> : <Menu size={20} />}
      </button>

      {/* Overlay */}
      {open && (
        <div
          className="fixed inset-0 bg-black/50 z-30 md:hidden"
          onClick={() => setOpen(false)}
        />
      )}

      {/* Sidebar */}
      <aside
        className={`fixed left-0 top-0 h-full w-64 bg-slate-900 text-white z-40 transform transition-transform duration-200
          ${open ? 'translate-x-0' : '-translate-x-full'} md:translate-x-0 md:static md:block`}
      >
        <div className="p-6 border-b border-slate-700">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 bg-blue-500 rounded-xl flex items-center justify-center font-bold text-lg">V</div>
            <div>
              <div className="font-bold text-sm leading-tight">Villa 207</div>
              <div className="text-slate-400 text-xs">Financial System</div>
            </div>
          </div>
        </div>

        <nav className="p-4 space-y-1">
          {navItems.map((item) => (
            <button
              key={item.view}
              onClick={() => { setView(item.view); setOpen(false) }}
              className={`w-full flex items-center gap-3 px-4 py-3 rounded-xl text-sm font-medium transition-colors
                ${view === item.view
                  ? 'bg-blue-600 text-white'
                  : 'text-slate-400 hover:bg-slate-800 hover:text-white'
                }`}
            >
              {item.icon}
              {item.label}
            </button>
          ))}
        </nav>
      </aside>
    </>
  )
}
