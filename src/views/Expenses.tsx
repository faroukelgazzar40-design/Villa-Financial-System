import { useState, useMemo } from 'react'
import { Plus, Pencil, Trash2, Upload, Download, Search, RefreshCw } from 'lucide-react'
import { useStore } from '../store'
import { MonthPicker } from '../components/MonthPicker'
import { ExpenseForm } from '../components/ExpenseForm'
import { ExpenseTxn } from '../types'
import { formatEGP } from '../utils/format'
import { exportExpensesCSV, parseExpensesCSV } from '../utils/csv'
import { format, parseISO, startOfMonth, endOfMonth, isWithinInterval } from 'date-fns'

function inMonth(date: string, month: string): boolean {
  const d = parseISO(date)
  const ref = parseISO(month + '-01')
  return isWithinInterval(d, { start: startOfMonth(ref), end: endOfMonth(ref) })
}

export function Expenses() {
  const { expenses, deleteExpense, importExpenses, selectedMonth } = useStore()
  const [showForm, setShowForm] = useState(false)
  const [editing, setEditing] = useState<ExpenseTxn | undefined>()
  const [search, setSearch] = useState('')
  const [filterCat, setFilterCat] = useState('')

  const monthData = useMemo(() => expenses.filter((t) => inMonth(t.date, selectedMonth)), [expenses, selectedMonth])

  const filtered = useMemo(() => {
    return monthData
      .filter((t) => !search || JSON.stringify(t).toLowerCase().includes(search.toLowerCase()))
      .filter((t) => !filterCat || t.category === filterCat)
      .sort((a, b) => b.date.localeCompare(a.date))
  }, [monthData, search, filterCat])

  const total = filtered.reduce((s, t) => s + t.amount, 0)

  // Group by category for summary
  const byCategory = useMemo(() => {
    const map: Record<string, number> = {}
    for (const t of monthData) map[t.category] = (map[t.category] || 0) + t.amount
    return Object.entries(map).sort((a, b) => b[1] - a[1])
  }, [monthData])

  async function handleImport(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0]
    if (!file) return
    const txns = await parseExpensesCSV(file)
    importExpenses(txns)
    e.target.value = ''
  }

  return (
    <div className="p-6 space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold text-slate-800">Expenses</h1>
          <p className="text-sm text-slate-500 mt-0.5">{filtered.length} transactions · {formatEGP(total)}</p>
        </div>
        <div className="flex items-center gap-2 flex-wrap">
          <MonthPicker />
          <label className="cursor-pointer flex items-center gap-1.5 border border-slate-200 rounded-xl px-3 py-2 text-sm text-slate-600 hover:bg-slate-50">
            <Upload size={14} /> Import CSV
            <input type="file" accept=".csv" className="hidden" onChange={handleImport} />
          </label>
          <button
            onClick={() => exportExpensesCSV(filtered, `expenses-${selectedMonth}.csv`)}
            className="flex items-center gap-1.5 border border-slate-200 rounded-xl px-3 py-2 text-sm text-slate-600 hover:bg-slate-50"
          >
            <Download size={14} /> Export
          </button>
          <button
            onClick={() => { setEditing(undefined); setShowForm(true) }}
            className="flex items-center gap-1.5 bg-red-500 text-white rounded-xl px-4 py-2 text-sm font-medium hover:bg-red-600"
          >
            <Plus size={16} /> Add Expense
          </button>
        </div>
      </div>

      {/* Category summary */}
      {byCategory.length > 0 && (
        <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-3">
          {byCategory.slice(0, 4).map(([cat, amount]) => (
            <div key={cat} className="bg-white border border-slate-200 rounded-xl px-4 py-3">
              <p className="text-xs text-slate-500 mb-1">{cat}</p>
              <p className="font-semibold text-slate-700">{formatEGP(amount)}</p>
            </div>
          ))}
        </div>
      )}

      {/* Filters */}
      <div className="flex gap-3 flex-wrap">
        <div className="relative flex-1 min-w-[200px]">
          <Search size={14} className="absolute left-3 top-1/2 -translate-y-1/2 text-slate-400" />
          <input type="text" placeholder="Search..." value={search} onChange={(e) => setSearch(e.target.value)}
            className="w-full pl-8 pr-3 py-2 border border-slate-200 rounded-xl text-sm focus:outline-none focus:ring-2 focus:ring-red-400" />
        </div>
        <select value={filterCat} onChange={(e) => setFilterCat(e.target.value)}
          className="border border-slate-200 rounded-xl px-3 py-2 text-sm focus:outline-none">
          <option value="">All Categories</option>
          {[...new Set(monthData.map((t) => t.category))].map((c) => <option key={c}>{c}</option>)}
        </select>
      </div>

      {/* Table */}
      <div className="bg-white rounded-2xl border border-slate-200 overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-slate-100 bg-slate-50">
                <th className="text-left px-4 py-3 font-medium text-slate-500">Date</th>
                <th className="text-left px-4 py-3 font-medium text-slate-500">Category</th>
                <th className="text-left px-4 py-3 font-medium text-slate-500">Description</th>
                <th className="text-left px-4 py-3 font-medium text-slate-500">Branch</th>
                <th className="text-left px-4 py-3 font-medium text-slate-500">Payment</th>
                <th className="text-left px-4 py-3 font-medium text-slate-500">Type</th>
                <th className="text-right px-4 py-3 font-medium text-slate-500">Amount</th>
                <th className="px-4 py-3"></th>
              </tr>
            </thead>
            <tbody>
              {filtered.length === 0 && (
                <tr><td colSpan={8} className="text-center py-12 text-slate-400">No expenses found</td></tr>
              )}
              {filtered.map((t) => (
                <tr key={t.id} className="border-b border-slate-50 hover:bg-slate-50 transition-colors">
                  <td className="px-4 py-3 text-slate-600">{format(parseISO(t.date), 'dd MMM')}</td>
                  <td className="px-4 py-3">
                    <span className="bg-red-50 text-red-700 rounded-lg px-2 py-0.5 text-xs font-medium">{t.category}</span>
                  </td>
                  <td className="px-4 py-3 text-slate-600">{t.description || '—'}</td>
                  <td className="px-4 py-3 text-slate-500 text-xs">{t.branch}</td>
                  <td className="px-4 py-3 text-slate-500 text-xs">{t.paymentMethod}</td>
                  <td className="px-4 py-3">
                    {t.isRecurring && (
                      <span className="flex items-center gap-1 text-purple-600 text-xs">
                        <RefreshCw size={11} /> Fixed
                      </span>
                    )}
                  </td>
                  <td className="px-4 py-3 text-right font-semibold text-red-600">{formatEGP(t.amount)}</td>
                  <td className="px-4 py-3">
                    <div className="flex items-center gap-1 justify-end">
                      <button onClick={() => { setEditing(t); setShowForm(true) }}
                        className="p-1.5 text-slate-400 hover:text-blue-600 hover:bg-blue-50 rounded-lg">
                        <Pencil size={14} />
                      </button>
                      <button onClick={() => { if (confirm('Delete this expense?')) deleteExpense(t.id) }}
                        className="p-1.5 text-slate-400 hover:text-red-600 hover:bg-red-50 rounded-lg">
                        <Trash2 size={14} />
                      </button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
            {filtered.length > 0 && (
              <tfoot>
                <tr className="bg-slate-50 font-semibold">
                  <td colSpan={6} className="px-4 py-3 text-slate-600">Total</td>
                  <td className="px-4 py-3 text-right text-red-600">{formatEGP(total)}</td>
                  <td />
                </tr>
              </tfoot>
            )}
          </table>
        </div>
      </div>

      {showForm && (
        <ExpenseForm
          existing={editing}
          onClose={() => { setShowForm(false); setEditing(undefined) }}
        />
      )}
    </div>
  )
}
