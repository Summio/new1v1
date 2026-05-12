export const nicknameUploadTargets = [
  {
    value: 'male-prefixes',
    label: '男生前缀',
    gender: 'male',
    section: 'prefixes',
  },
  {
    value: 'male-suffixes',
    label: '男生后缀',
    gender: 'male',
    section: 'suffixes',
  },
  {
    value: 'female-prefixes',
    label: '女生前缀',
    gender: 'female',
    section: 'prefixes',
  },
  {
    value: 'female-suffixes',
    label: '女生后缀',
    gender: 'female',
    section: 'suffixes',
  },
]

export function resolveNicknameUploadTarget(target) {
  return (
    nicknameUploadTargets.find((item) => item.value === target) ?? nicknameUploadTargets[0]
  )
}
