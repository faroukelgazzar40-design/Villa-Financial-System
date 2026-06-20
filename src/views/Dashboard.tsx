import { useMemo } from 'react'
import { TrendingUp, TrendingDown, DollarSign, Activity } from 'lucide-react'
import {
  BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer, Legend,
  PieChart, Pie, Cell, LineChart, Line,
} from 'recharts'
import { useStore } from '../store'
import { StatCard } from '../components/StatCard'
import { MonthPicker } from '../components/MonthPicker'
import { formatEGP, formatNumber } from '../utils/format'
import { format, parseISO, startOfMonth, endOfMonth, isWithinInterval } from 'date-fns'
import { IncomeTxn, ExpenseTxn } from '../types'

const BRANCH_COLORS = { '6 October': '#3b82f6', 'Nasr City': '#8b5cf6' }
const CAT_COLORS = ['#3b82f6', '#8b5cf6', '#10b981', '#f59e0b', '#ef4444', '#06b6d4', '#ec4899', '#84cc16', '#f97316']

function inMonth(date: string, month: string): boolean {
  const d = parseISO(date)
  const ref = parseISO(month + '-01')
  return isWithinInterval(d, { start: startOfMonth(ref), end: endOfMonth(ref) })
}

export function Dashboard() {
  const { income, expenses, selectedMonth } = useStore()

  const monthIncome = useMemo(() => income.filter((t) => inMonth(t.date, selectedMonth)), [income, selectedMonth])
  const monthExpenses = useMemo(() => expenses.filter((t) => inMonth(t.date, selectedMonth)), [expenses, selectedMonth])

  const totalIncome = monthIncome.reduce((s, t) => s + t.amount, 0)
  const totalExpenses = monthExpenses.reduce((s, t) => s + t.amount, 0)
  const netProfit = totalIncome - totalExpenses

  // Revenue by category
  const byCategory = useMemo(() => {
    const map: Record<string, number> = {}
    for (const t of monthIncome) {
      map[t.category] = (map[t.category] || 0) + t.amount
    }
    return Object.entries(map)
      .map(([name, value]) => ({ name, value }))
      .sort((a, b) => b.value - a.value)
  }, [monthIncome])

  // Revenue by branch
  const byBranch = useMemo(() => {
    const inc: Record<string, number> = {}
    const exp: Record<string, number> = {}
    for (const t of monthIncome) inc[t.branch] = (inc[t.branch] || 0) + t.amount
    for (const t of monthExpenses) exp[t.branch] = (exp[t.branch] || 0) + t.amount
    return ['6 October', 'Nasr City'].map((b) => ({
      branch: b,
      Income: inc[b] || 0,
      Expenses: exp[b] || 0,
      'Net Profit': (inc[b] || 0) - (exp[b] || 0),
    }))
  }, [monthIncome, monthExpenses])

  // Sales person performance
  const bySalesPerson = useMemo(() => {
    const map: Record<string, number> = {}
    for (const t of monthIncome) {
      map[t.salesPerson] = (map[t.salesPerson] || 0) + t.amount
    }
    return Object.entries(map)
      .map(([name, value]) => ({ name, value }))
      .sort((a, b) => b.value - a.value)
      .slice(0, 8)
  }, [monthIncome])

  // Last 6 months trend
  const trend = useMemo(() => {
    const months: string[] = []
    const ref = parseISO(selectedMonth + '-01')
    for (let i = 5; i >= 0; i--) {
      const d = new Date(ref)
      d.setMonth(d.getMonth() - i)
      months.push(format(d, 'yyyy-MM'))
    }
    return months.map((m) => {
      const inc = income.filter((t) => inMonth(t.date, m)).reduce((s, t) => s + t.amount, 0)
      const exp = expenses.filter((t) => inMonth(t.date, m)).reduce((s, t) => s + t.amount, 0)
      return { month: format(parseISO(m + '-01'), 'MMM yy'), Income: inc, Expenses: exp, 'Net Profit': inc - exp }
    })
  }, [income, expenses, selectedMonth])

  return (
    <div className="p-6 space-y-6">
      <div className="flex flex-wrap items-center justify-between gap-4">
        <h1 className="text-2xl font-bold text-slate-800">Dashboard</h1>
        <MonthPicker />
      </div>

      {/* KPI cards */}
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
        <StatCard title="Total Revenue" value={totalIncome} icon={<TrendingUp size={20} />} color="green" subtitle={`${monthIncome.length} transactions`} />
        <StatCard title="Total Expenses" value={totalExpenses} icon={<TrendingDown size={20} />} color="red" subtitle={`${monthExpenses.length} transactions`} />
        <StatCard title="Net Profit" value={netProfit} icon={<DollarSign size={20} />} color={netProfit >= 0 ? 'blue' : 'red'} />
        <StatCard title="Margin" value={totalIncome > 0 ? Math.round((netProfit / totalIncome) * 100) : 0} icon={<Activity size={20} />} color="purple" subtitle="% of revenue" />
      </div>

      {/* Charts row 1 */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* 6-month trend */}
        <div className="bg-white rounded-2xl border border-slate-200 p-5">
          <h2 className="font-semibold text-slate-700 mb-4">6-Month Trend</h2>
          <ResponsiveContainer width="100%" height={220}>
            <LineChart data={trend}>
              <XAxis dataKey="month" tick={{ fontSize: 11 }} />
              <YAxis tick={{ fontSize: 11 }} tickFormatter={(v) => `${(v / 1000).toFixed(0)}k`} />
              <Tooltip formatter={(v) => formatEGP(Number(v ?? 0))} />
              <Legend />
              <Line type="monotone" dataKey="Income" stroke="#10b981" strokeWidth={2} dot={false} />
              <Line type="monotone" dataKey="Expenses" stroke="#ef4444" strokeWidth={2} dot={false} />
              <Line type="monotone" dataKey="Net Profit" stroke="#3b82f6" strokeWidth={2} dot={false} />
            </LineChart>
          </ResponsiveContainer>
        </div>

        {/* Branch comparison */}
        <div className="bg-white rounded-2xl border border-slate-200 p-5">
          <h2 className="font-semibold text-slate-700 mb-4">Branch Comparison</h2>
          <ResponsiveContainer width="100%" height={220}>
            <BarChart data={byBranch}>
              <XAxis dataKey="branch" tick={{ fontSize: 11 }} />
              <YAxis tick={{ fontSize: 11 }} tickFormatter={(v) => `${(v / 1000).toFixed(0)}k`} />
              <Tooltip formatter={(v) => formatEGP(Number(v ?? 0))} />
              <Legend />
              <Bar dataKey="Income" fill="#10b981" radius={[4, 4, 0, 0]} />
              <Bar dataKey="Expenses" fill="#ef4444" radius={[4, 4, 0, 0]} />
              <Bar dataKey="Net Profit" fill="#3b82f6" radius={[4, 4, 0, 0]} />
            </BarChart>
          </ResponsiveContainer>
        </div>
      </div>

      {/* Charts row 2 */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Revenue by category */}
        <div className="bg-white rounded-2xl border border-slate-200 p-5">
          <h2 className="font-semibold text-slate-700 mb-4">Revenue by Category</h2>
          {byCategory.length === 0 ? (
            <p className="text-slate-400 text-sm text-center py-10">No income data for this month</p>
          ) : (
            <div className="flex gap-4 items-center">
              <ResponsiveContainer width="50%" height={200}>
                <PieChart>
                  <Pie data={byCategory} dataKey="value" nameKey="name" cx="50%" cy="50%" outerRadius={80} label={false}>
                    {byCategory.map((_, i) => <Cell key={i} fill={CAT_COLORS[i % CAT_COLORS.length]} />)}
                  </Pie>
                  <Tooltip formatter={(v) => formatEGP(Number(v ?? 0))} />
                </PieChart>
              </ResponsiveContainer>
              <div className="flex-1 space-y-2">
                {byCategory.map((item, i) => (
                  <div key={item.name} className="flex items-center justify-between text-xs">
                    <div className="flex items-center gap-1.5">
                      <div className="w-2.5 h-2.5 rounded-full" style={{ background: CAT_COLORS[i % CAT_COLORS.length] }} />
                      <span className="text-slate-600">{item.name}</span>
                    </div>
                    <span className="font-semibold text-slate-700">{formatNumber(item.value)}</span>
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>

        {/* Sales person performance */}
        <div className="bg-white rounded-2xl border border-slate-200 p-5">
          <h2 className="font-semibold text-slate-700 mb-4">Sales Person Performance</h2>
          {bySalesPerson.length === 0 ? (
            <p className="text-slate-400 text-sm text-center py-10">No data for this month</p>
          ) : (
            <div className="space-y-3">
              {bySalesPerson.map((item, i) => (
                <div key={item.name}>
                  <div className="flex justify-between text-xs mb-1">
                    <span className="text-slate-600">{item.name}</span>
                    <span className="font-semibold">{formatEGP(item.value)}</span>
                  </div>
                  <div className="h-2 bg-slate-100 rounded-full">
                    <div
                      className="h-2 rounded-full"
                      style={{
                        width: `${(item.value / bySalesPerson[0].value) * 100}%`,
                        background: CAT_COLORS[i % CAT_COLORS.length],
                      }}
                    />
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
      </div>
    </div>
  )
}
