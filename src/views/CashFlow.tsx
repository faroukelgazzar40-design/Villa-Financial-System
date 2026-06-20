import { useMemo } from 'react'
import { useStore } from '../store'
import { MonthPicker } from '../components/MonthPicker'
import { formatEGP } from '../utils/format'
import {
  AreaChart, Area, XAxis, YAxis, Tooltip, ResponsiveContainer,
} from 'recharts'
import { format, parseISO, startOfMonth, endOfMonth, eachDayOfInterval, isWithinInterval } from 'date-fns'

export function CashFlow() {
  const { income, expenses, selectedMonth } = useStore()

  const { dailyData, totalIncome, totalExpenses, endBalance } = useMemo(() => {
    const ref = parseISO(selectedMonth + '-01')
    const start = startOfMonth(ref)
    const end = endOfMonth(ref)
    const days = eachDayOfInterval({ start, end })

    let runningBalance = 0

    const dailyData = days.map((day) => {
      const dayStr = format(day, 'yyyy-MM-dd')
      const dayIncome = income
        .filter((t) => t.date === dayStr)
        .reduce((s, t) => s + t.amount, 0)
      const dayExpense = expenses
        .filter((t) => t.date === dayStr)
        .reduce((s, t) => s + t.amount, 0)
      runningBalance += dayIncome - dayExpense

      return {
        date: format(day, 'dd MMM'),
        'Cash In': dayIncome,
        'Cash Out': dayExpense,
        'Running Balance': runningBalance,
      }
    })

    const totalIncome = income
      .filter((t) => isWithinInterval(parseISO(t.date), { start, end }))
      .reduce((s, t) => s + t.amount, 0)

    const totalExpenses = expenses
      .filter((t) => isWithinInterval(parseISO(t.date), { start, end }))
      .reduce((s, t) => s + t.amount, 0)

    return { dailyData, totalIncome, totalExpenses, endBalance: runningBalance }
  }, [income, expenses, selectedMonth])

  const activeDays = dailyData.filter((d) => d['Cash In'] > 0 || d['Cash Out'] > 0)

  return (
    <div className="p-6 space-y-6">
      <div className="flex flex-wrap items-center justify-between gap-4">
        <h1 className="text-2xl font-bold text-slate-800">Cash Flow</h1>
        <MonthPicker />
      </div>

      {/* Summary */}
      <div className="grid grid-cols-3 gap-4">
        <div className="bg-green-50 border border-green-100 rounded-2xl p-5">
          <p className="text-xs text-green-600 font-medium mb-1">Total Cash In</p>
          <p className="text-xl font-bold text-green-700">{formatEGP(totalIncome)}</p>
        </div>
        <div className="bg-red-50 border border-red-100 rounded-2xl p-5">
          <p className="text-xs text-red-600 font-medium mb-1">Total Cash Out</p>
          <p className="text-xl font-bold text-red-700">{formatEGP(totalExpenses)}</p>
        </div>
        <div className={`${endBalance >= 0 ? 'bg-blue-50 border-blue-100' : 'bg-red-50 border-red-100'} border rounded-2xl p-5`}>
          <p className={`text-xs font-medium mb-1 ${endBalance >= 0 ? 'text-blue-600' : 'text-red-600'}`}>Month-End Balance</p>
          <p className={`text-xl font-bold ${endBalance >= 0 ? 'text-blue-700' : 'text-red-700'}`}>{formatEGP(endBalance)}</p>
        </div>
      </div>

      {/* Running balance chart */}
      <div className="bg-white rounded-2xl border border-slate-200 p-5">
        <h2 className="font-semibold text-slate-700 mb-4">Running Balance</h2>
        <ResponsiveContainer width="100%" height={260}>
          <AreaChart data={dailyData}>
            <defs>
              <linearGradient id="balanceGrad" x1="0" y1="0" x2="0" y2="1">
                <stop offset="5%" stopColor="#3b82f6" stopOpacity={0.15} />
                <stop offset="95%" stopColor="#3b82f6" stopOpacity={0} />
              </linearGradient>
            </defs>
            <XAxis dataKey="date" tick={{ fontSize: 10 }} interval={4} />
            <YAxis tick={{ fontSize: 10 }} tickFormatter={(v) => `${(v / 1000).toFixed(0)}k`} />
            <Tooltip formatter={(v) => formatEGP(Number(v ?? 0))} />
            <Area type="monotone" dataKey="Running Balance" stroke="#3b82f6" fill="url(#balanceGrad)" strokeWidth={2} />
          </AreaChart>
        </ResponsiveContainer>
      </div>

      {/* Daily cash in/out */}
      <div className="bg-white rounded-2xl border border-slate-200 p-5">
        <h2 className="font-semibold text-slate-700 mb-4">Daily Cash In / Out</h2>
        <ResponsiveContainer width="100%" height={220}>
          <AreaChart data={dailyData}>
            <XAxis dataKey="date" tick={{ fontSize: 10 }} interval={4} />
            <YAxis tick={{ fontSize: 10 }} tickFormatter={(v) => `${(v / 1000).toFixed(0)}k`} />
            <Tooltip formatter={(v) => formatEGP(Number(v ?? 0))} />
            <Area type="monotone" dataKey="Cash In" stroke="#10b981" fill="#d1fae5" strokeWidth={2} />
            <Area type="monotone" dataKey="Cash Out" stroke="#ef4444" fill="#fee2e2" strokeWidth={2} />
          </AreaChart>
        </ResponsiveContainer>
      </div>

      {/* Day-by-day table (only active days) */}
      {activeDays.length > 0 && (
        <div className="bg-white rounded-2xl border border-slate-200 overflow-hidden">
          <div className="p-4 border-b border-slate-100">
            <h2 className="font-semibold text-slate-700">Daily Breakdown</h2>
          </div>
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-slate-100 bg-slate-50">
                  <th className="text-left px-4 py-3 font-medium text-slate-500">Date</th>
                  <th className="text-right px-4 py-3 font-medium text-slate-500">Cash In</th>
                  <th className="text-right px-4 py-3 font-medium text-slate-500">Cash Out</th>
                  <th className="text-right px-4 py-3 font-medium text-slate-500">Net</th>
                  <th className="text-right px-4 py-3 font-medium text-slate-500">Running Balance</th>
                </tr>
              </thead>
              <tbody>
                {activeDays.map((d) => {
                  const net = d['Cash In'] - d['Cash Out']
                  return (
                    <tr key={d.date} className="border-b border-slate-50 hover:bg-slate-50">
                      <td className="px-4 py-2.5 text-slate-600">{d.date}</td>
                      <td className="px-4 py-2.5 text-right text-green-600 font-medium">{d['Cash In'] > 0 ? formatEGP(d['Cash In']) : '—'}</td>
                      <td className="px-4 py-2.5 text-right text-red-500 font-medium">{d['Cash Out'] > 0 ? formatEGP(d['Cash Out']) : '—'}</td>
                      <td className={`px-4 py-2.5 text-right font-semibold ${net >= 0 ? 'text-green-600' : 'text-red-500'}`}>{formatEGP(net)}</td>
                      <td className={`px-4 py-2.5 text-right font-bold ${d['Running Balance'] >= 0 ? 'text-blue-600' : 'text-red-600'}`}>{formatEGP(d['Running Balance'])}</td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </div>
  )
}
