import Papa from 'papaparse'
import { IncomeTxn, ExpenseTxn } from '../types'

export function exportIncomeCSV(txns: IncomeTxn[], filename: string) {
  const csv = Papa.unparse(txns.map((t) => ({
    id: t.id,
    date: t.date,
    amount: t.amount,
    salesPerson: t.salesPerson,
    category: t.category,
    space: t.space,
    paymentMethod: t.paymentMethod,
    paymentStatus: t.paymentStatus,
    branch: t.branch,
    comment: t.comment,
  })))
  downloadCSV(csv, filename)
}

export function exportExpensesCSV(txns: ExpenseTxn[], filename: string) {
  const csv = Papa.unparse(txns.map((t) => ({
    id: t.id,
    date: t.date,
    amount: t.amount,
    category: t.category,
    description: t.description,
    paymentMethod: t.paymentMethod,
    branch: t.branch,
    isRecurring: t.isRecurring,
    comment: t.comment,
  })))
  downloadCSV(csv, filename)
}

function downloadCSV(csv: string, filename: string) {
  const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = filename
  a.click()
  URL.revokeObjectURL(url)
}

export function parseIncomeCSV(file: File): Promise<IncomeTxn[]> {
  return new Promise((resolve, reject) => {
    Papa.parse(file, {
      header: true,
      skipEmptyLines: true,
      complete: (results) => {
        const txns = (results.data as Record<string, string>[]).map((row) => ({
          id: row.id || `import-${Date.now()}-${Math.random()}`,
          date: row.date || '',
          amount: parseFloat(row.amount) || 0,
          salesPerson: row.salesPerson || row['Sales Person'] || '',
          category: row.category || row.Category || 'Other',
          space: row.space || row.Space || '',
          paymentMethod: row.paymentMethod || row['Payment Method'] || 'Cash',
          paymentStatus: row.paymentStatus || row['Payment Status'] || 'Done',
          branch: row.branch || row.Branch || '6 October',
          comment: row.comment || row.Comment || '',
        })) as IncomeTxn[]
        resolve(txns)
      },
      error: reject,
    })
  })
}

export function parseExpensesCSV(file: File): Promise<ExpenseTxn[]> {
  return new Promise((resolve, reject) => {
    Papa.parse(file, {
      header: true,
      skipEmptyLines: true,
      complete: (results) => {
        const txns = (results.data as Record<string, string>[]).map((row) => ({
          id: row.id || `import-${Date.now()}-${Math.random()}`,
          date: row.date || '',
          amount: parseFloat(row.amount) || 0,
          category: row.category || row.Category || 'Others',
          description: row.description || row.Description || '',
          paymentMethod: row.paymentMethod || row['Payment Method'] || 'Cash',
          branch: row.branch || row.Branch || '6 October',
          isRecurring: row.isRecurring === 'true',
          comment: row.comment || row.Comment || '',
        })) as ExpenseTxn[]
        resolve(txns)
      },
      error: reject,
    })
  })
}
