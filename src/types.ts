export type Branch = '6 October' | 'Nasr City'

export type PaymentMethod = 'Cash' | 'Bank Transfer' | 'Instapay' | 'Vodafone Cash' | 'Cheque'

export type PaymentStatus = 'Done' | 'Pending' | 'Partial'

export type IncomeCategory =
  | 'Office Space'
  | 'Virtual Office'
  | 'Meeting Room'
  | 'Market/Bar'
  | 'Coworking'
  | 'HR'
  | 'Commission'
  | 'Registration Fee'
  | 'Other'

export type ExpenseCategory =
  | 'Rent'
  | 'Salaries'
  | 'Ads'
  | 'Market'
  | 'Maintenance'
  | 'Electricity'
  | 'Internet'
  | 'Transportation'
  | 'Assets'
  | 'Mobile'
  | 'Cleaning'
  | 'Registration Fee'
  | 'Commission'
  | 'Bank Fees'
  | 'Stationery'
  | 'Others'

export interface IncomeTxn {
  id: string
  date: string // ISO date string YYYY-MM-DD
  amount: number
  salesPerson: string
  category: IncomeCategory
  space: string
  paymentMethod: PaymentMethod
  paymentStatus: PaymentStatus
  branch: Branch
  comment: string
}

export interface ExpenseTxn {
  id: string
  date: string
  amount: number
  category: ExpenseCategory
  description: string
  paymentMethod: PaymentMethod
  branch: Branch
  isRecurring: boolean
  comment: string
}

export type View = 'dashboard' | 'income' | 'expenses' | 'cashflow'

export const SALES_PEOPLE = [
  'Villa',
  'Yasmen',
  'Rokaya',
  'Shorouk',
  'Rahma',
  'Mariam',
  'Shahd',
  'Shaimaa',
  'Yassmen Abdelnaby',
  'Other',
]

export const INCOME_CATEGORIES: IncomeCategory[] = [
  'Office Space',
  'Virtual Office',
  'Meeting Room',
  'Market/Bar',
  'Coworking',
  'HR',
  'Commission',
  'Registration Fee',
  'Other',
]

export const EXPENSE_CATEGORIES: ExpenseCategory[] = [
  'Rent',
  'Salaries',
  'Ads',
  'Market',
  'Maintenance',
  'Electricity',
  'Internet',
  'Transportation',
  'Assets',
  'Mobile',
  'Cleaning',
  'Registration Fee',
  'Commission',
  'Bank Fees',
  'Stationery',
  'Others',
]

export const PAYMENT_METHODS: PaymentMethod[] = [
  'Cash',
  'Bank Transfer',
  'Instapay',
  'Vodafone Cash',
  'Cheque',
]

export const BRANCHES: Branch[] = ['6 October', 'Nasr City']
