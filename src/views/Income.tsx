import { useState, useMemo } from 'react'
import { Plus, Pencil, Trash2, Upload, Download, Search } from 'lucide-react'
import { useStore } from '../store'
import { MonthPicker } from '../components/MonthPicker'
import { IncomeForm } from '../components/IncomeForm'
import { IncomeTxn } from '../types'
import { formatEGP } from '../utils/format'
import { exportIncomeCSV, parseIncomeCSV } from '../utils/csv'
import { format, parseISO, startOfMonth, endOfMonth, isWithinInterval } from 'date-fns'

function inMonth(date: string, month: string): boolean {
  const d = parseISO(date)
  const ref = parseISO(month + '-01')
  return isWithinInterval(d, { start: startOfMonth(ref), end: endOfMonth(ref) })
}

const STATUS_COLOR: Record<string, string> = {
  Done: 'bg-green-100 text-green-700',
  Pending: 'bg-yellow-100 text-yellow-700',
  Partial: 'bg-orange-100 text-orange-700',
}

export function Income() {
  const { income, deleteIncome, importIncome, selectedMonth } = useStore()
  const [showForm, setShowForm] = useState(false)
  const [editing, setEditing] = useState<IncomeTxn | undefined>()
  const [search, setSearch] = useState('')
  const [filterCat, setFilterCat] = useState('')
  const [filterBranch, setFilterBranch] = useState('')

  const monthData = useMemo(() => income.filter((t) => inMonth(t.date, selectedMonth)), [income, selectedMonth])

  const filtered = useMemo(() => {
    return monthData
      .filter((t) => !search || JSON.stringify(t).toLowerCase().includes(search.toLowerCase()))
      .filter((t) => !filterCat || t.category === filterCat)
      .filter((t) => !filterBranch || t.branch === filterBranch)
      .sort((a, b) => b.date.localeCompare(a.date))
  }, [monthData, search, filterCat, filterBranch])

  const total = filtered.reduce((s, t) => s + t.amount, 0)

  async function handleImport(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0]
    if (!file) return
    const txns = await parseIncomeCSV(file)
    importIncome(txns)
    e.target.value = ''
  }

  return (
    <div className="p-6 space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold text-slate-800">Income</h1>
          <p className="text-sm text-slate-500 mt-0.5">{filtered.length} transactions · {formatEGP(total)}</p>
        </div>
        <div className="flex items-center gap-2 flex-wrap">
          <MonthPicker />
          <label className="cursor-pointer flex items-center gap-1.5 border border-slate-200 rounded-xl px-3 py-2 text-sm text-slate-600 hover:bg-slate-50">
            <Upload size={14} /> Import CSV
            <input type="file" accept=".csv" className="hidden" onChange={handleImport} />
          </label>
          <button
            onClick={() => exportIncomeCSV(filtered, `income-${selectedMonth}.csv`)}
            className="flex items-center gap-1.5 border border-slate-200 rounded-xl px-3 py-2 text-sm text-slate-600 hover:bg-slate-50"
          >
            <Download size={14} /> Export
          </button>
          <button
            onClick={() => { setEditing(undefined); setShowForm(true) }}
            className="flex items-center gap-1.5 bg-blue-600 text-white rounded-xl px-4 py-2 text-sm font-medium hover:bg-blue-700"
          >
            <Plus size={16} /> Add Income
          </button>
        </div>
      </div>

      {/* Filters */}
      <div className="flex gap-3 flex-wrap">
        <div className="relative flex-1 min-w-[200px]">
          <Search size={14} className="absolute left-3 top-1/2 -translate-y-1/2 text-slate-400" />
          <input
            type="text"
            placeholder="Search..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="w-full pl-8 pr-3 py-2 border border-slate-200 rounded-xl text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
          />
        </div>
        <select value={filterCat} onChange={(e) => setFilterCat(e.target.value)}
          className="border border-slate-200 rounded-xl px-3 py-2 text-sm focus:outline-none">
          <option value="">All Categories</option>
          {[...new Set(monthData.map((t) => t.category))].map((c) => <option key={c}>{c}</option>)}
        </select>
        <select value={filterBranch} onChange={(e) => setFilterBranch(e.target.value)}
          className="border border-slate-200 rounded-xl px-3 py-2 text-sm focus:outline-none">
          <option value="">All Branches</option>
          <option>6 October</option>
          <option>Nasr City</option>
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
                <th className="text-left px-4 py-3 font-medium text-slate-500">Space</th>
                <th className="text-left px-4 py-3 font-medium text-slate-500">Sales Person</th>
                <th className="text-left px-4 py-3 font-medium text-slate-500">Branch</th>
                <th className="text-left px-4 py-3 font-medium text-slate-500">Payment</th>
                <th className="text-left px-4 py-3 font-medium text-slate-500">Status</th>
                <th className="text-right px-4 py-3 font-medium text-slate-500">Amount</th>
                <th className="px-4 py-3"></th>
              </tr>
            </thead>
            <tbody>
              {filtered.length === 0 && (
                <tr>
                  <td colSpan={9} className="text-center py-12 text-slate-400">No transactions found</td>
                </tr>
              )}
              {filtered.map((t) => (
                <tr key={t.id} className="border-b border-slate-50 hover:bg-slate-50 transition-colors">
                  <td className="px-4 py-3 text-slate-600">{format(parseISO(t.date), 'dd MMM')}</td>
                  <td className="px-4 py-3">
                    <span className="bg-blue-50 text-blue-700 rounded-lg px-2 py-0.5 text-xs font-medium">{t.category}</span>
                  </td>
                  <td className="px-4 py-3 text-slate-600">{t.space || '—'}</td>
                  <td className="px-4 py-3 text-slate-700">{t.salesPerson}</td>
                  <td className="px-4 py-3 text-slate-500 text-xs">{t.branch}</td>
                  <td className="px-4 py-3 text-slate-500 text-xs">{t.paymentMethod}</td>
                  <td className="px-4 py-3">
                    <span className={`rounded-lg px-2 py-0.5 text-xs font-medium ${STATUS_COLOR[t.paymentStatus] || ''}`}>
                      {t.paymentStatus}
                    </span>
                  </td>
                  <td className="px-4 py-3 text-right font-semibold text-green-700">{formatEGP(t.amount)}</td>
                  <td className="px-4 py-3">
                    <div className="flex items-center gap-1 justify-end">
                      <button onClick={() => { setEditing(t); setShowForm(true) }}
                        className="p-1.5 text-slate-400 hover:text-blue-600 hover:bg-blue-50 rounded-lg">
                        <Pencil size={14} />
                      </button>
                      <button onClick={() => { if (confirm('Delete this transaction?')) deleteIncome(t.id) }}
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
                  <td colSpan={7} className="px-4 py-3 text-slate-600">Total</td>
                  <td className="px-4 py-3 text-right text-green-700">{formatEGP(total)}</td>
                  <td />
                </tr>
              </tfoot>
            )}
          </table>
        </div>
      </div>

      {showForm && (
        <IncomeForm
          existing={editing}
          onClose={() => { setShowForm(false); setEditing(undefined) }}
        />
      )}
    </div>
  )
}
