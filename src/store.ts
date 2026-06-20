import { create } from 'zustand'
import { persist } from 'zustand/middleware'
import { IncomeTxn, ExpenseTxn, View } from './types'
import { format } from 'date-fns'

interface FinancialStore {
  income: IncomeTxn[]
  expenses: ExpenseTxn[]
  view: View
  selectedMonth: string // YYYY-MM

  setView: (view: View) => void
  setSelectedMonth: (month: string) => void
  addIncome: (txn: Omit<IncomeTxn, 'id'>) => void
  updateIncome: (id: string, txn: Partial<IncomeTxn>) => void
  deleteIncome: (id: string) => void
  addExpense: (txn: Omit<ExpenseTxn, 'id'>) => void
  updateExpense: (id: string, txn: Partial<ExpenseTxn>) => void
  deleteExpense: (id: string) => void
  importIncome: (txns: IncomeTxn[]) => void
  importExpenses: (txns: ExpenseTxn[]) => void
}

function generateId(): string {
  return `${Date.now()}-${Math.random().toString(36).slice(2, 9)}`
}

export const useStore = create<FinancialStore>()(
  persist(
    (set) => ({
      income: [],
      expenses: [],
      view: 'dashboard',
      selectedMonth: format(new Date(), 'yyyy-MM'),

      setView: (view) => set({ view }),
      setSelectedMonth: (selectedMonth) => set({ selectedMonth }),

      addIncome: (txn) =>
        set((s) => ({ income: [...s.income, { ...txn, id: generateId() }] })),

      updateIncome: (id, txn) =>
        set((s) => ({
          income: s.income.map((t) => (t.id === id ? { ...t, ...txn } : t)),
        })),

      deleteIncome: (id) =>
        set((s) => ({ income: s.income.filter((t) => t.id !== id) })),

      addExpense: (txn) =>
        set((s) => ({ expenses: [...s.expenses, { ...txn, id: generateId() }] })),

      updateExpense: (id, txn) =>
        set((s) => ({
          expenses: s.expenses.map((t) => (t.id === id ? { ...t, ...txn } : t)),
        })),

      deleteExpense: (id) =>
        set((s) => ({ expenses: s.expenses.filter((t) => t.id !== id) })),

      importIncome: (txns) =>
        set((s) => {
          const existingIds = new Set(s.income.map((t) => t.id))
          const newTxns = txns.filter((t) => !existingIds.has(t.id))
          return { income: [...s.income, ...newTxns] }
        }),

      importExpenses: (txns) =>
        set((s) => {
          const existingIds = new Set(s.expenses.map((t) => t.id))
          const newTxns = txns.filter((t) => !existingIds.has(t.id))
          return { expenses: [...s.expenses, ...newTxns] }
        }),
    }),
    { name: 'villa-financial-v1' }
  )
)
