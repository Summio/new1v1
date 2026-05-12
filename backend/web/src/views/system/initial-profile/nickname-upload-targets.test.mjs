import assert from 'node:assert/strict'
import test from 'node:test'

import {
  nicknameUploadTargets,
  resolveNicknameUploadTarget,
} from './nickname-upload-targets.mjs'

test('nickname upload targets expose all supported options', () => {
  assert.deepEqual(
    nicknameUploadTargets.map((item) => item.value),
    ['male-prefixes', 'male-suffixes', 'female-prefixes', 'female-suffixes']
  )
})

test('resolveNicknameUploadTarget returns structured target info', () => {
  assert.deepEqual(resolveNicknameUploadTarget('female-suffixes'), {
    value: 'female-suffixes',
    label: '女生后缀',
    gender: 'female',
    section: 'suffixes',
  })
})

test('resolveNicknameUploadTarget falls back to male prefixes', () => {
  assert.deepEqual(resolveNicknameUploadTarget('unknown'), {
    value: 'male-prefixes',
    label: '男生前缀',
    gender: 'male',
    section: 'prefixes',
  })
})
