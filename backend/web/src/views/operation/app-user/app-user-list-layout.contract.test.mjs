import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const source = readFileSync(new URL('./index.vue', import.meta.url), 'utf8')

test('app user list hides profile column but keeps view edit action', () => {
  const columnsStart = source.indexOf('const columns = [')
  const templateStart = source.indexOf('</script>')
  assert.notEqual(columnsStart, -1)
  assert.notEqual(templateStart, -1)

  const columnsSource = source.slice(columnsStart, templateStart)
  assert.equal(columnsSource.includes("title: '资料信息'"), false)
  assert.equal(columnsSource.includes("{ default: () => '查看/编辑' }"), true)
  assert.equal(source.includes('title="查看/编辑 App用户"'), true)
})

test('app user account column shows gender below nickname', () => {
  const accountStart = source.indexOf("title: '账号信息'")
  const statusStart = source.indexOf("title: '状态'", accountStart)
  assert.notEqual(accountStart, -1)
  assert.notEqual(statusStart, -1)

  const accountColumnSource = source.slice(accountStart, statusStart)
  assert.equal(accountColumnSource.includes("infoLine('手机号'"), true)
  assert.equal(accountColumnSource.includes("infoLine('昵称'"), true)
  assert.equal(accountColumnSource.includes("infoLine('性别'"), true)
  assert.equal(accountColumnSource.indexOf("infoLine('昵称'") < accountColumnSource.indexOf("infoLine('性别'"), true)
})
