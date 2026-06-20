import { ReactNode } from 'react'
import { formatEGP } from '../utils/format'

interface StatCardProps {
  title: string
  value: number
  icon: ReactNode
  color: 'green' | 'red' | 'blue' | 'purple'
  subtitle?: string
}

const colorMap = {
  green: 'bg-green-50 text-green-600 border-green-100',
  red: 'bg-red-50 text-red-600 border-red-100',
  blue: 'bg-blue-50 text-blue-600 border-blue-100',
  purple: 'bg-purple-50 text-purple-600 border-purple-100',
}

const iconColorMap = {
  green: 'bg-green-100 text-green-600',
  red: 'bg-red-100 text-red-600',
  blue: 'bg-blue-100 text-blue-600',
  purple: 'bg-purple-100 text-purple-600',
}

export function StatCard({ title, value, icon, color, subtitle }: StatCardProps) {
  return (
    <div className={`rounded-2xl border p-5 ${colorMap[color]}`}>
      <div className="flex items-start justify-between">
        <div>
          <p className="text-sm font-medium opacity-70">{title}</p>
          <p className="text-2xl font-bold mt-1">{formatEGP(value)}</p>
          {subtitle && <p className="text-xs mt-1 opacity-60">{subtitle}</p>}
        </div>
        <div className={`p-2.5 rounded-xl ${iconColorMap[color]}`}>{icon}</div>
      </div>
    </div>
  )
}
