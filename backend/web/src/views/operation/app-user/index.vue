<script setup>
import { computed, h, onMounted, reactive, ref, watch } from 'vue'
import {
  NButton,
  NDataTable,
  NForm,
  NFormItem,
  NImage,
  NInput,
  NInputNumber,
  NModal,
  NSelect,
  NSwitch,
  NTabPane,
  NTag,
  NTabs,
} from 'naive-ui'

import CommonPage from '@/components/page/CommonPage.vue'
import QueryBarItem from '@/components/query-bar/QueryBarItem.vue'
import CrudTable from '@/components/table/CrudTable.vue'
import api from '@/api'
import { formatDate } from '@/utils'

defineOptions({ name: 'App用户管理' })

const $table = ref(null)
const queryItems = ref({})
const editModalVisible = ref(false)
const saving = ref(false)
const activeEditTab = ref('basic')
const modalForm = ref({
  id: null,
  phone: '',
  nickname: '',
  avatar: '',
  signature: '',
  gender: 'secret',
  birth_date: '',
  height_cm: null,
  weight_kg: null,
  location_city: '',
  status: 'normal',
  is_certified_user: false,
  is_recommended: false,
  recommend_weight: 0,
  certification_status: 'none',
  certification_reject_reason: '',
  certification_face_image: '',
  certified_call_price: 0,
  cover_url: '',
  album_photos: [],
  coins: 0,
  diamonds: 0,
  frozen_diamonds: 0,
  created_at: '',
  last_login: '',
})
const callRecordLoading = ref(false)
const callRecordRows = ref([])
const peerJumpLoading = ref(false)
const billLoading = ref(false)
const billRows = ref([])
const certifiedCallPriceAllOptions = ref([{ label: '免费', value: 0 }])
const certifiedCallPriceFreeOptions = computed(() => [{ label: '免费', value: 0 }])
const certifiedCallPricePaidOptions = computed(() =>
  certifiedCallPriceAllOptions.value.filter((option) => option.value > 0)
)
const certifiedCallPriceOptions = computed(() =>
  modalForm.value.is_certified_user
    ? certifiedCallPricePaidOptions.value
    : certifiedCallPriceFreeOptions.value
)
const billSummary = reactive({
  income_coins_total: 0,
  income_diamonds_total: 0,
  expense_coins_total: 0,
  expense_diamonds_total: 0,
})
const callRecordQuery = reactive({
  status: null,
  end_reason: null,
})
const billQuery = reactive({
  direction: 'all',
  biz_type: null,
})
const callRecordPagination = reactive({
  page: 1,
  pageSize: 6,
  itemCount: 0,
  pageSizes: [6, 10, 20],
  showSizePicker: true,
  prefix({ itemCount }) {
    return `共 ${itemCount} 条`
  },
  onChange(page) {
    callRecordPagination.page = page
    fetchUserCallRecords()
  },
  onUpdatePageSize(pageSize) {
    callRecordPagination.pageSize = pageSize
    callRecordPagination.page = 1
    fetchUserCallRecords()
  },
})
const billPagination = reactive({
  page: 1,
  pageSize: 8,
  itemCount: 0,
  pageSizes: [8, 12, 20],
  showSizePicker: true,
  prefix({ itemCount }) {
    return `共 ${itemCount} 条`
  },
  onChange(page) {
    billPagination.page = page
    fetchUserBills()
  },
  onUpdatePageSize(pageSize) {
    billPagination.pageSize = pageSize
    billPagination.page = 1
    fetchUserBills()
  },
})

onMounted(() => {
  fetchCertifiedCallPriceOptions()
  $table.value?.handleSearch()
})

watch(
  () => [
    modalForm.value.is_certified_user,
    certifiedCallPricePaidOptions.value.map((option) => option.value).join(','),
  ],
  () => normalizeModalCallPrice()
)

const statusOptions = [
  { label: '正常', value: 'normal' },
  { label: '封禁', value: 'banned' },
]

const genderOptions = [
  { label: '男', value: 'male' },
  { label: '女', value: 'female' },
  { label: '保密', value: 'secret' },
]

const certificationOptions = [
  { label: '真人认证', value: true },
  { label: '普通用户', value: false },
]
const certificationStatusOptions = [
  { label: '未申请', value: 'none' },
  { label: '待审核', value: 'pending' },
  { label: '已通过', value: 'approved' },
  { label: '已驳回', value: 'rejected' },
]

async function fetchCertifiedCallPriceOptions() {
  try {
    const res = await api.getCertifiedCallPriceConfig()
    const tiers = Array.isArray(res?.data?.tiers) ? res.data.tiers : []
    const normalized = Array.from(
      new Set(
        tiers.map((item) => Number(item)).filter((item) => Number.isInteger(item) && item >= 0)
      )
    ).sort((a, b) => a - b)
    if (!normalized.includes(0)) normalized.unshift(0)
    certifiedCallPriceAllOptions.value = normalized.map((value) => ({
      label: value === 0 ? '免费' : `${value}金币/分钟`,
      value,
    }))
    normalizeModalCallPrice()
  } catch (error) {
    certifiedCallPriceAllOptions.value = [{ label: '免费', value: 0 }]
    normalizeModalCallPrice()
  }
}

function normalizeModalCallPrice() {
  if (!modalForm.value.is_certified_user) {
    modalForm.value.certified_call_price = 0
    return
  }
  const paidOptions = certifiedCallPricePaidOptions.value
  if (!paidOptions.length) {
    modalForm.value.certified_call_price = 0
    return
  }
  const currentPrice = Number(modalForm.value.certified_call_price || 0)
  if (!paidOptions.some((option) => option.value === currentPrice)) {
    modalForm.value.certified_call_price = paidOptions[0].value
  }
}
const callRecordStatusOptions = [
  { label: '待接听', value: 'pending' },
  { label: '通话中', value: 'ongoing' },
  { label: '已结束', value: 'ended' },
  { label: '失败', value: 'failed' },
  { label: '超时', value: 'timeout' },
]
const callRecordEndReasonOptions = [
  { label: '正常结束', value: 'normal' },
  { label: '被叫拒接', value: 'rejected' },
  { label: '主叫取消', value: 'cancelled' },
  { label: '呼叫超时', value: 'timeout' },
  { label: '余额不足', value: 'balance_empty' },
  { label: '用户离场', value: 'force_exit' },
]
const callRecordStatusMap = {
  pending: { type: 'warning', text: '待接听' },
  ongoing: { type: 'info', text: '通话中' },
  ended: { type: 'success', text: '已结束' },
  failed: { type: 'error', text: '失败' },
  timeout: { type: 'default', text: '超时' },
}
const callRecordEndReasonMap = {
  normal: '正常结束',
  rejected: '被叫拒接',
  cancelled: '主叫取消',
  timeout: '呼叫超时',
  balance_empty: '余额不足',
  force_exit: '用户离场',
}
const billDirectionOptions = [
  { label: '全部', value: 'all' },
  { label: '仅收入', value: 'income' },
  { label: '仅支出', value: 'expense' },
]
const billBizTypeOptions = [
  { label: '全部业务', value: null },
  { label: '充值', value: 'recharge' },
  { label: '通话', value: 'call' },
  { label: '礼物', value: 'gift' },
  { label: '提现', value: 'withdraw' },
]
const billBizTypeTextMap = {
  recharge: '充值',
  call: '通话',
  gift: '礼物',
  withdraw: '提现',
}
const billAssetTypeTextMap = {
  coins: '金币',
  diamonds: '钻石',
}

const avatarImgStyle = {
  width: '44px',
  height: '44px',
  minWidth: '44px',
  minHeight: '44px',
  maxWidth: '44px',
  maxHeight: '44px',
  borderRadius: '8px',
  objectFit: 'cover',
  border: '1px solid #eceff5',
  display: 'block',
}

const coverImgStyle = {
  width: '36px',
  height: '36px',
  minWidth: '36px',
  minHeight: '36px',
  maxWidth: '36px',
  maxHeight: '36px',
  borderRadius: '8px',
  objectFit: 'cover',
  border: '1px solid #eceff5',
  display: 'block',
}

function normalizeAlbum(v) {
  if (!Array.isArray(v)) return []
  return v.filter((item) => typeof item === 'string' && item.trim()).map((item) => item.trim())
}

function infoLine(label, value) {
  return h('div', { class: 'meta-line' }, [
    h('span', { class: 'meta-label' }, `${label}：`),
    h('span', { class: 'meta-value' }, value || '-'),
  ])
}

function openEditModal(row) {
  const album = normalizeAlbum(row.album_photos)
  modalForm.value = {
    id: row.id,
    phone: row.phone || '',
    nickname: row.nickname || '',
    avatar: row.avatar || '',
    signature: row.signature || '',
    gender: row.gender || 'secret',
    birth_date: row.birth_date || '',
    height_cm: row.height_cm ?? null,
    weight_kg: row.weight_kg ?? null,
    location_city: row.location_city || '',
    status: row.status || 'normal',
    is_certified_user: !!row.is_certified_user,
    is_recommended: !!row.is_recommended,
    recommend_weight: row.recommend_weight ?? 0,
    certification_status: row.certification_status || 'none',
    certification_reject_reason: row.certification_reject_reason || '',
    certification_face_image: row.certification_face_image || '',
    certified_call_price: row.is_certified_user ? Number(row.certified_call_price || 0) : 0,
    cover_url: row.cover_url || '',
    album_photos: album,
    coins: row.coins ?? 0,
    diamonds: row.diamonds ?? 0,
    frozen_diamonds: row.frozen_diamonds ?? 0,
    created_at: row.created_at || '',
    last_login: row.last_login || '',
  }
  activeEditTab.value = 'basic'
  callRecordRows.value = []
  callRecordPagination.page = 1
  callRecordPagination.itemCount = 0
  callRecordQuery.status = null
  callRecordQuery.end_reason = null
  billRows.value = []
  billPagination.page = 1
  billPagination.itemCount = 0
  billQuery.direction = 'all'
  billQuery.biz_type = null
  billSummary.income_coins_total = 0
  billSummary.income_diamonds_total = 0
  billSummary.expense_coins_total = 0
  billSummary.expense_diamonds_total = 0
  normalizeModalCallPrice()
  editModalVisible.value = true
}

function handleViewEdit(row) {
  openEditModal(row)
}

function formatDuration(seconds) {
  const total = Number(seconds || 0)
  const hVal = Math.floor(total / 3600)
  const mVal = Math.floor((total % 3600) / 60)
  const sVal = total % 60
  if (hVal > 0) return `${hVal}小时 ${mVal}分 ${sVal}秒`
  if (mVal > 0) return `${mVal}分 ${sVal}秒`
  return `${sVal}秒`
}

function formatSharePercent(bps) {
  const value = Number(bps || 0)
  if (!Number.isFinite(value) || value <= 0) return '-'
  return `${(value / 100).toFixed(2)}%`
}

function resolvePeerInfo(row) {
  const currentId = Number(modalForm.value.id || 0)
  const callerId = Number(row.caller_id || 0)
  const isCaller = currentId === callerId
  const peerId = isCaller ? row.callee_id : row.caller_id
  const peerNickname = isCaller ? row.callee_nickname : row.caller_nickname
  const peerPhone = isCaller ? row.callee_phone : row.caller_phone
  return {
    peerId: Number(peerId || 0),
    text: `ID:${peerId} ${peerNickname || '-'} / ${peerPhone || '-'}`,
  }
}

async function handleOpenPeerUser(row) {
  const peer = resolvePeerInfo(row)
  if (!peer.peerId) return
  if (peer.peerId === Number(modalForm.value.id || 0)) return
  peerJumpLoading.value = true
  try {
    const res = await api.getAppUserById({ id: peer.peerId })
    if (res?.data) {
      openEditModal(res.data)
    }
  } catch (error) {
    window.$message?.error(error?.message || '加载对端用户失败')
  } finally {
    peerJumpLoading.value = false
  }
}

const callRecordColumns = [
  { title: '通话ID', key: 'id', width: 80, align: 'center' },
  {
    title: '对端用户',
    key: 'peer',
    minWidth: 180,
    render(row) {
      const peer = resolvePeerInfo(row)
      return h(
        NButton,
        {
          text: true,
          type: 'primary',
          disabled: !peer.peerId || peerJumpLoading.value,
          loading: peerJumpLoading.value,
          onClick: () => handleOpenPeerUser(row),
        },
        { default: () => peer.text }
      )
    },
  },
  {
    title: '状态',
    key: 'status',
    width: 90,
    align: 'center',
    render(row) {
      const item = callRecordStatusMap[row.status] || { type: 'default', text: row.status || '-' }
      return h(NTag, { type: item.type }, { default: () => item.text })
    },
  },
  {
    title: '结束原因',
    key: 'end_reason',
    width: 110,
    align: 'center',
    render(row) {
      if (!row.end_reason) return '-'
      return callRecordEndReasonMap[row.end_reason] || row.end_reason
    },
  },
  {
    title: '时长',
    key: 'duration',
    width: 90,
    align: 'center',
    render: (row) => formatDuration(row.duration),
  },
  { title: '总费用(金币)', key: 'total_fee', width: 100, align: 'center' },
  {
    title: '收益认证用户',
    key: 'income_certified_user_id',
    width: 100,
    align: 'center',
    render(row) {
      return row.income_certified_user_id || '-'
    },
  },
  {
    title: '认证用户收益(钻石)',
    key: 'certified_user_income_diamonds',
    width: 130,
    align: 'center',
    render(row) {
      return Number(row.certified_user_income_diamonds || 0)
    },
  },
  {
    title: '分成比例',
    key: 'certified_user_share_bps',
    width: 100,
    align: 'center',
    render(row) {
      return formatSharePercent(row.certified_user_share_bps)
    },
  },
  {
    title: '收益结算时间',
    key: 'income_settled_at',
    width: 160,
    align: 'center',
    render(row) {
      return row.income_settled_at ? formatDate(row.income_settled_at, 'YYYY-MM-DD HH:mm:ss') : '-'
    },
  },
  {
    title: '创建时间',
    key: 'created_at',
    width: 150,
    align: 'center',
    render(row) {
      return row.created_at ? formatDate(row.created_at, 'YYYY-MM-DD HH:mm:ss') : '-'
    },
  },
]

const billColumns = [
  { title: '账单ID', key: 'id', width: 140, align: 'center' },
  {
    title: '类型',
    key: 'direction',
    width: 90,
    align: 'center',
    render(row) {
      const isIncome = !!row.is_income
      return h(
        NTag,
        { type: isIncome ? 'success' : 'error' },
        { default: () => (isIncome ? '收入' : '支出') }
      )
    },
  },
  {
    title: '业务',
    key: 'biz_type',
    width: 90,
    align: 'center',
    render(row) {
      return billBizTypeTextMap[row.biz_type] || row.biz_type || '-'
    },
  },
  {
    title: '关联方',
    key: 'related_user',
    minWidth: 200,
    render(row) {
      const relatedId = row.related_user_id
      const relatedNickname = row.related_user_nickname || '-'
      if (!relatedId) return relatedNickname
      return `ID:${relatedId} ${relatedNickname}`
    },
  },
  {
    title: '说明',
    key: 'title',
    minWidth: 220,
    render(row) {
      return row.title || '-'
    },
  },
  {
    title: '金额',
    key: 'amount',
    width: 140,
    align: 'right',
    render(row) {
      const amount = Number(row.amount || 0)
      const prefix = row.is_income ? '+' : '-'
      const unit = billAssetTypeTextMap[row.asset_type] || row.asset_type || ''
      return `${prefix}${amount}${unit}`
    },
  },
  {
    title: '时间',
    key: 'created_at',
    width: 170,
    align: 'center',
    render(row) {
      return row.created_at ? formatDate(row.created_at, 'YYYY-MM-DD HH:mm:ss') : '-'
    },
  },
]

async function fetchUserCallRecords() {
  if (!modalForm.value.id) return
  callRecordLoading.value = true
  try {
    const res = await api.getCallRecordList({
      user_id: modalForm.value.id,
      page: callRecordPagination.page,
      page_size: callRecordPagination.pageSize,
      status: callRecordQuery.status || undefined,
      end_reason: callRecordQuery.end_reason || undefined,
    })
    callRecordRows.value = res?.data || []
    callRecordPagination.itemCount = Number(res?.total || 0)
  } catch (error) {
    callRecordRows.value = []
    callRecordPagination.itemCount = 0
  } finally {
    callRecordLoading.value = false
  }
}

async function handleSearchUserCallRecords() {
  callRecordPagination.page = 1
  await fetchUserCallRecords()
}

async function handleResetUserCallRecords() {
  callRecordQuery.status = null
  callRecordQuery.end_reason = null
  callRecordPagination.page = 1
  await fetchUserCallRecords()
}

async function fetchUserBills() {
  if (!modalForm.value.id) return
  billLoading.value = true
  try {
    const res = await api.getAppUserBillList({
      user_id: modalForm.value.id,
      page: billPagination.page,
      page_size: billPagination.pageSize,
      direction: billQuery.direction || 'all',
      biz_type: billQuery.biz_type || undefined,
    })
    billRows.value = res?.data || []
    billPagination.itemCount = Number(res?.total || 0)
    billSummary.income_coins_total = Number(res?.income_coins_total || 0)
    billSummary.income_diamonds_total = Number(res?.income_diamonds_total || 0)
    billSummary.expense_coins_total = Number(res?.expense_coins_total || 0)
    billSummary.expense_diamonds_total = Number(res?.expense_diamonds_total || 0)
  } catch (error) {
    billRows.value = []
    billPagination.itemCount = 0
    billSummary.income_coins_total = 0
    billSummary.income_diamonds_total = 0
    billSummary.expense_coins_total = 0
    billSummary.expense_diamonds_total = 0
  } finally {
    billLoading.value = false
  }
}

async function handleSearchUserBills() {
  billPagination.page = 1
  await fetchUserBills()
}

async function handleResetUserBills() {
  billQuery.direction = 'all'
  billQuery.biz_type = null
  billPagination.page = 1
  await fetchUserBills()
}

async function handleEditTabChange(name) {
  activeEditTab.value = name
  if (name === 'call_records' && !callRecordRows.value.length) {
    await fetchUserCallRecords()
    return
  }
  if (name === 'bills' && !billRows.value.length) {
    await fetchUserBills()
  }
}

async function handleSave() {
  if (!modalForm.value.id) return
  normalizeModalCallPrice()
  if (modalForm.value.is_certified_user && !certifiedCallPricePaidOptions.value.length) {
    $message?.warning('请先配置至少一个收费通话价格档位')
    return
  }
  if (modalForm.value.is_certified_user && Number(modalForm.value.certified_call_price || 0) <= 0) {
    $message?.warning('真人认证用户不能设置免费通话价格')
    return
  }
  saving.value = true
  try {
    const album = normalizeAlbum(modalForm.value.album_photos)
    const payload = {
      id: modalForm.value.id,
      nickname: (modalForm.value.nickname || '').trim(),
      avatar: (modalForm.value.avatar || '').trim(),
      signature: (modalForm.value.signature || '').trim(),
      gender: modalForm.value.gender || 'secret',
      birth_date: (modalForm.value.birth_date || '').trim() || null,
      height_cm: modalForm.value.height_cm ?? null,
      weight_kg: modalForm.value.weight_kg ?? null,
      location_city: (modalForm.value.location_city || '').trim(),
      status: modalForm.value.status || 'normal',
      is_certified_user: !!modalForm.value.is_certified_user,
      is_recommended: !!modalForm.value.is_recommended,
      recommend_weight: modalForm.value.recommend_weight ?? 0,
      certification_status: modalForm.value.certification_status || 'none',
      certification_reject_reason:
        (modalForm.value.certification_reject_reason || '').trim() || null,
      certification_face_image: (modalForm.value.certification_face_image || '').trim(),
      certified_call_price: modalForm.value.is_certified_user
        ? Number(modalForm.value.certified_call_price || 0)
        : 0,
      album_photos: album,
      cover_url: (modalForm.value.cover_url || '').trim(),
    }
    await api.updateAppUser(payload)
    $message?.success('保存成功')
    editModalVisible.value = false
    $table.value?.handleSearch()
  } catch (error) {
    $message?.error(error?.message || '保存失败')
  } finally {
    saving.value = false
  }
}

function chooseImageFile() {
  return new Promise((resolve) => {
    const input = document.createElement('input')
    input.type = 'file'
    input.accept = 'image/png,image/jpeg,image/webp'
    input.onchange = () => {
      const file = input.files && input.files.length ? input.files[0] : null
      resolve(file)
    }
    input.click()
  })
}

async function uploadImage(file) {
  if (!file) return ''
  const formData = new FormData()
  formData.append('file', file)
  const res = await api.uploadAppUserImage(formData)
  return res?.data?.url || ''
}

async function handleUploadAvatar() {
  try {
    const file = await chooseImageFile()
    if (!file) return
    const url = await uploadImage(file)
    if (!url) return
    modalForm.value.avatar = url
    window.$message?.success('头像上传成功')
  } catch (error) {
    window.$message?.error(error?.message || '头像上传失败')
  }
}

async function handleAddAlbumPhoto() {
  if ((modalForm.value.album_photos || []).length >= 6) {
    window.$message?.warning('相册最多6张')
    return
  }
  try {
    const file = await chooseImageFile()
    if (!file) return
    const url = await uploadImage(file)
    if (!url) return
    modalForm.value.album_photos = [...(modalForm.value.album_photos || []), url]
    if (!modalForm.value.cover_url) {
      modalForm.value.cover_url = url
    }
    window.$message?.success('相册上传成功')
  } catch (error) {
    window.$message?.error(error?.message || '相册上传失败')
  }
}

async function handleReplaceAlbumPhoto(index) {
  try {
    const file = await chooseImageFile()
    if (!file) return
    const url = await uploadImage(file)
    if (!url) return
    const next = [...(modalForm.value.album_photos || [])]
    const old = next[index]
    next[index] = url
    modalForm.value.album_photos = next
    if (modalForm.value.cover_url === old) {
      modalForm.value.cover_url = url
    }
    window.$message?.success('照片已替换')
  } catch (error) {
    window.$message?.error(error?.message || '替换失败')
  }
}

function handleRemoveAlbumPhoto(index) {
  const next = [...(modalForm.value.album_photos || [])]
  const removed = next[index]
  next.splice(index, 1)
  modalForm.value.album_photos = next
  if (modalForm.value.cover_url === removed) {
    modalForm.value.cover_url = next[0] || ''
  }
}

function handleSetCover(url) {
  modalForm.value.cover_url = url || ''
}

const columns = [
  { title: 'ID', key: 'id', width: 60, align: 'center' },
  {
    title: '头像',
    key: 'avatar',
    width: 86,
    align: 'center',
    render(row) {
      if (!row.avatar) return '-'
      return h(NImage, {
        src: row.avatar,
        width: 44,
        height: 44,
        objectFit: 'cover',
        previewDisabled: false,
        imgProps: {
          class: 'avatar-thumb',
          style: avatarImgStyle,
          alt: 'avatar',
        },
      })
    },
  },
  {
    title: '账号信息',
    key: 'account',
    width: 200,
    render(row) {
      return h('div', { class: 'meta-wrap' }, [
        infoLine('手机号', row.phone || '-'),
        infoLine('昵称', row.nickname || '-'),
      ])
    },
  },
  {
    title: '资料信息',
    key: 'profile',
    width: 260,
    render(row) {
      const genderMap = { male: '男', female: '女', secret: '保密' }
      const hw = [
        row.height_cm ? `${row.height_cm}cm` : '',
        row.weight_kg ? `${row.weight_kg}kg` : '',
      ]
        .filter(Boolean)
        .join(' / ')
      return h('div', { class: 'meta-wrap' }, [
        infoLine('性别', genderMap[row.gender] || '保密'),
        infoLine('生日', row.birth_date || '-'),
        infoLine('身高体重', hw || '-'),
        infoLine('所在地', row.location_city || '-'),
      ])
    },
  },
  {
    title: '相册/封面',
    key: 'album_cover',
    width: 220,
    render(row) {
      const album = normalizeAlbum(row.album_photos)
      const cover = row.cover_url || ''
      return h('div', { class: 'album-summary' }, [
        h('div', { class: 'album-summary-top' }, [
          cover
            ? h(NImage, {
                src: cover,
                width: 36,
                height: 36,
                objectFit: 'cover',
                previewDisabled: false,
                imgProps: {
                  class: 'cover-thumb',
                  style: coverImgStyle,
                  alt: 'cover',
                },
              })
            : h('div', { class: 'cover-placeholder' }, '无封面'),
          h('div', { class: 'album-summary-meta' }, [
            h('div', { class: 'album-head' }, `相册 ${album.length} 张`),
            h('div', { class: 'album-sub' }, cover ? '已设置封面' : '未设置封面'),
          ]),
        ]),
      ])
    },
  },
  {
    title: '状态',
    key: 'status',
    width: 80,
    align: 'center',
    render(row) {
      const isBanned = row.status === 'banned'
      return h(
        NTag,
        { type: isBanned ? 'error' : 'success' },
        { default: () => (isBanned ? '封禁' : '正常') }
      )
    },
  },
  {
    title: '真人认证',
    key: 'is_certified_user',
    width: 70,
    align: 'center',
    render(row) {
      return h(
        NTag,
        { type: row.is_certified_user ? 'warning' : 'default' },
        { default: () => (row.is_certified_user ? '是' : '否') }
      )
    },
  },
  { title: '金币', key: 'coins', width: 90, align: 'center' },
  { title: '钻石', key: 'diamonds', width: 90, align: 'center' },
  { title: '冻结钻石', key: 'frozen_diamonds', width: 100, align: 'center' },
  {
    title: '创建时间',
    key: 'created_at',
    width: 140,
    align: 'center',
    render(row) {
      return row.created_at ? formatDate(row.created_at) : ''
    },
  },
  {
    title: '最后登录',
    key: 'last_login',
    width: 140,
    align: 'center',
    render(row) {
      return row.last_login ? formatDate(row.last_login) : ''
    },
  },
  {
    title: '操作',
    key: 'actions',
    width: 100,
    align: 'center',
    fixed: 'right',
    render(row) {
      return h(
        NButton,
        {
          size: 'small',
          type: 'primary',
          onClick: () => handleViewEdit(row),
        },
        { default: () => '查看/编辑' }
      )
    },
  },
]
</script>

<template>
  <CommonPage show-footer title="App用户列表">
    <CrudTable
      ref="$table"
      v-model:query-items="queryItems"
      :columns="columns"
      :get-data="api.getAppUserList"
    >
      <template #queryBar>
        <QueryBarItem label="手机号" :label-width="60">
          <NInput
            v-model:value="queryItems.phone"
            clearable
            type="text"
            placeholder="请输入手机号"
            @keypress.enter="$table?.handleSearch()"
          />
        </QueryBarItem>
        <QueryBarItem label="昵称" :label-width="50">
          <NInput
            v-model:value="queryItems.nickname"
            clearable
            type="text"
            placeholder="请输入昵称"
            @keypress.enter="$table?.handleSearch()"
          />
        </QueryBarItem>
        <QueryBarItem label="性别" :label-width="50">
          <NSelect
            v-model:value="queryItems.gender"
            clearable
            style="width: 140px"
            :options="genderOptions"
            placeholder="请选择性别"
          />
        </QueryBarItem>
        <QueryBarItem label="所在地" :label-width="60">
          <NInput
            v-model:value="queryItems.location_city"
            clearable
            type="text"
            placeholder="请输入城市"
            @keypress.enter="$table?.handleSearch()"
          />
        </QueryBarItem>
        <QueryBarItem label="状态" :label-width="50">
          <NSelect
            v-model:value="queryItems.status"
            clearable
            style="width: 160px"
            :options="statusOptions"
            placeholder="请选择状态"
          />
        </QueryBarItem>
        <QueryBarItem label="真人认证" :label-width="50">
          <NSelect
            v-model:value="queryItems.is_certified_user"
            clearable
            style="width: 160px"
            :options="certificationOptions"
            placeholder="请选择类型"
          />
        </QueryBarItem>
      </template>
    </CrudTable>

    <NModal
      v-model:show="editModalVisible"
      preset="card"
      title="查看/编辑 App用户"
      style="width: 1120px"
    >
      <NTabs :value="activeEditTab" type="line" animated @update:value="handleEditTabChange">
        <NTabPane name="basic" tab="基础信息">
          <NForm label-placement="left" label-width="90" class="edit-form-grid">
            <NFormItem label="用户ID">
              <NInput :value="String(modalForm.id || '')" readonly />
            </NFormItem>
            <NFormItem label="手机号">
              <NInput v-model:value="modalForm.phone" readonly />
            </NFormItem>
            <NFormItem label="昵称">
              <NInput v-model:value="modalForm.nickname" />
            </NFormItem>
            <NFormItem label="个性签名" class="full-span">
              <NInput
                v-model:value="modalForm.signature"
                type="textarea"
                :autosize="{ minRows: 2, maxRows: 4 }"
                placeholder="用于App认证用户详情页“关于我”展示"
              />
            </NFormItem>
            <NFormItem label="性别">
              <NSelect v-model:value="modalForm.gender" :options="genderOptions" />
            </NFormItem>
            <NFormItem label="出生日期">
              <NInput v-model:value="modalForm.birth_date" placeholder="YYYY-MM-DD" />
            </NFormItem>
            <NFormItem label="所在地">
              <NInput v-model:value="modalForm.location_city" placeholder="省-市" />
            </NFormItem>
            <NFormItem label="身高(cm)">
              <NInputNumber v-model:value="modalForm.height_cm" style="width: 100%" clearable />
            </NFormItem>
            <NFormItem label="体重(kg)">
              <NInputNumber v-model:value="modalForm.weight_kg" style="width: 100%" clearable />
            </NFormItem>
            <NFormItem label="状态">
              <NSelect v-model:value="modalForm.status" :options="statusOptions" />
            </NFormItem>
            <NFormItem label="真人认证">
              <NSwitch v-model:value="modalForm.is_certified_user" />
            </NFormItem>
            <NFormItem label="通话价格">
              <NSelect
                v-model:value="modalForm.certified_call_price"
                :options="certifiedCallPriceOptions"
                :disabled="!modalForm.is_certified_user || !certifiedCallPricePaidOptions.length"
              />
            </NFormItem>
            <NFormItem label="首页推荐">
              <NSwitch v-model:value="modalForm.is_recommended" />
            </NFormItem>
            <NFormItem label="推荐值">
              <NInputNumber
                v-model:value="modalForm.recommend_weight"
                style="width: 100%"
                :min="0"
                :precision="0"
              />
            </NFormItem>
            <NFormItem label="认证状态">
              <NSelect
                v-model:value="modalForm.certification_status"
                :options="certificationStatusOptions"
              />
            </NFormItem>
            <NFormItem label="驳回原因" class="full-span">
              <NInput
                v-model:value="modalForm.certification_reject_reason"
                type="textarea"
                :autosize="{ minRows: 2, maxRows: 4 }"
                placeholder="驳回申请时请填写原因"
              />
            </NFormItem>
          </NForm>
        </NTabPane>

        <NTabPane name="media" tab="媒体资料">
          <NForm label-placement="left" label-width="90">
            <NFormItem label="头像" class="full-span">
              <div class="media-row">
                <div class="media-thumb-lg">
                  <NImage
                    v-if="modalForm.avatar"
                    :src="modalForm.avatar"
                    width="92"
                    height="92"
                    object-fit="cover"
                  />
                  <span v-else>暂无头像</span>
                </div>
                <NButton type="primary" secondary @click="handleUploadAvatar">上传头像</NButton>
              </div>
            </NFormItem>
            <NFormItem label="封面" class="full-span">
              <div class="media-row">
                <div class="media-thumb-lg">
                  <NImage
                    v-if="modalForm.cover_url"
                    :src="modalForm.cover_url"
                    width="92"
                    height="92"
                    object-fit="cover"
                  />
                  <span v-else>未设置封面</span>
                </div>
                <NSelect
                  v-model:value="modalForm.cover_url"
                  :options="
                    (modalForm.album_photos || []).map((item, idx) => ({
                      label: `相册图 ${idx + 1}`,
                      value: item,
                    }))
                  "
                  placeholder="从相册中选择封面"
                  clearable
                  style="width: 220px"
                />
              </div>
            </NFormItem>
            <NFormItem label="相册" class="full-span">
              <div class="album-editor">
                <div class="album-actions">
                  <NButton type="primary" secondary @click="handleAddAlbumPhoto">新增照片</NButton>
                  <span class="hint">最多6张，点击“设为封面”即可切换封面</span>
                </div>
                <div v-if="(modalForm.album_photos || []).length" class="album-grid">
                  <div
                    v-for="(url, idx) in modalForm.album_photos"
                    :key="`${url}-${idx}`"
                    class="album-card"
                  >
                    <div class="media-thumb-md">
                      <NImage :src="url" width="100%" height="120" object-fit="cover" />
                    </div>
                    <div class="album-btns">
                      <NButton size="tiny" @click="handleReplaceAlbumPhoto(idx)">更换</NButton>
                      <NButton size="tiny" type="info" @click="handleSetCover(url)">
                        {{ modalForm.cover_url === url ? '当前封面' : '设为封面' }}
                      </NButton>
                      <NButton size="tiny" type="error" @click="handleRemoveAlbumPhoto(idx)"
                        >删除</NButton
                      >
                    </div>
                  </div>
                </div>
                <div v-else class="hint">暂无相册图片</div>
              </div>
            </NFormItem>
            <NFormItem label="认证正面照" class="full-span">
              <div class="media-row">
                <div class="media-thumb-lg">
                  <NImage
                    v-if="modalForm.certification_face_image"
                    :src="modalForm.certification_face_image"
                    width="92"
                    height="92"
                    object-fit="cover"
                  />
                  <span v-else>未上传</span>
                </div>
                <NInput
                  v-model:value="modalForm.certification_face_image"
                  placeholder="认证正面照URL（通常由App端上传）"
                  style="width: 420px"
                />
              </div>
            </NFormItem>
          </NForm>
        </NTabPane>

        <NTabPane name="call_records" tab="通话记录">
          <div class="call-record-query">
            <NSelect
              v-model:value="callRecordQuery.status"
              clearable
              :options="callRecordStatusOptions"
              placeholder="筛选状态"
              style="width: 150px"
            />
            <NSelect
              v-model:value="callRecordQuery.end_reason"
              clearable
              :options="callRecordEndReasonOptions"
              placeholder="筛选结束原因"
              style="width: 170px"
            />
            <NButton type="primary" @click="handleSearchUserCallRecords">查询</NButton>
            <NButton @click="handleResetUserCallRecords">重置</NButton>
          </div>
          <NDataTable
            :loading="callRecordLoading"
            :columns="callRecordColumns"
            :data="callRecordRows"
            :pagination="callRecordPagination"
            :scroll-x="1390"
            :bordered="false"
            :single-line="false"
          />
        </NTabPane>

        <NTabPane name="bills" tab="账单">
          <div class="call-record-query">
            <NSelect
              v-model:value="billQuery.direction"
              :options="billDirectionOptions"
              style="width: 150px"
              placeholder="账单方向"
            />
            <NSelect
              v-model:value="billQuery.biz_type"
              clearable
              :options="billBizTypeOptions"
              style="width: 160px"
              placeholder="业务类型"
            />
            <NButton type="primary" @click="handleSearchUserBills">查询</NButton>
            <NButton @click="handleResetUserBills">重置</NButton>
          </div>
          <div class="bill-summary">
            <div class="bill-summary-card income-coins">
              <div class="label">收入(金币)</div>
              <div class="value">{{ billSummary.income_coins_total }}</div>
            </div>
            <div class="bill-summary-card income-diamonds">
              <div class="label">收入(钻石)</div>
              <div class="value">{{ billSummary.income_diamonds_total }}</div>
            </div>
            <div class="bill-summary-card expense-coins">
              <div class="label">支出(金币)</div>
              <div class="value">{{ billSummary.expense_coins_total }}</div>
            </div>
            <div class="bill-summary-card expense-diamonds">
              <div class="label">支出(钻石)</div>
              <div class="value">{{ billSummary.expense_diamonds_total }}</div>
            </div>
          </div>
          <NDataTable
            :loading="billLoading"
            :columns="billColumns"
            :data="billRows"
            :pagination="billPagination"
            :scroll-x="1080"
            :bordered="false"
            :single-line="false"
          />
        </NTabPane>
      </NTabs>

      <template #action>
        <NButton @click="editModalVisible = false">取消</NButton>
        <NButton type="primary" :loading="saving" style="margin-left: 8px" @click="handleSave">
          保存
        </NButton>
      </template>
    </NModal>
  </CommonPage>
</template>

<style scoped>
.avatar-thumb {
  width: 44px;
  height: 44px;
  border-radius: 8px;
  object-fit: cover;
  border: 1px solid #eceff5;
}

.meta-wrap {
  display: flex;
  flex-direction: column;
  gap: 4px;
  line-height: 1.3;
}

.meta-line {
  display: flex;
  align-items: baseline;
}

.meta-label {
  color: #8b8f99;
  flex-shrink: 0;
}

.meta-value {
  color: #242933;
  word-break: break-all;
}

.album-head {
  color: #242933;
  font-weight: 600;
  white-space: nowrap;
  text-overflow: ellipsis;
  overflow: hidden;
}

.album-summary {
  display: flex;
  flex-direction: column;
  gap: 6px;
}

.album-summary-top {
  display: flex;
  align-items: center;
  gap: 8px;
  min-width: 0;
}

.album-summary-meta {
  min-width: 0;
}

.album-sub {
  color: #8b8f99;
  font-size: 12px;
}

.cover-placeholder {
  width: 36px;
  height: 36px;
  border-radius: 8px;
  border: 1px dashed #d7dbe3;
  display: flex;
  align-items: center;
  justify-content: center;
  color: #8b8f99;
  font-size: 10px;
}

.cover-row {
  display: flex;
  align-items: center;
  gap: 6px;
  min-width: 0;
  overflow: hidden;
}

.cover-thumb {
  width: 36px;
  height: 36px;
  border-radius: 8px;
  object-fit: cover;
  border: 1px solid #eceff5;
  flex: 0 0 auto;
}

.edit-form-grid {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  column-gap: 16px;
}

.full-span {
  grid-column: 1 / -1;
}

.media-row {
  display: flex;
  align-items: center;
  gap: 12px;
}

.media-thumb-lg {
  width: 92px;
  height: 92px;
  border: 1px dashed #d7dbe3;
  border-radius: 10px;
  overflow: hidden;
  display: flex;
  align-items: center;
  justify-content: center;
  color: #8b8f99;
  font-size: 12px;
}

.media-thumb-lg img {
  width: 100%;
  height: 100%;
  object-fit: cover;
}

.album-editor {
  width: 100%;
}

.album-actions {
  display: flex;
  align-items: center;
  gap: 10px;
  margin-bottom: 10px;
}

.hint {
  color: #8b8f99;
  font-size: 12px;
}

.album-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(150px, 1fr));
  gap: 10px;
}

.album-card {
  border: 1px solid #edf0f5;
  border-radius: 8px;
  padding: 8px;
}

.media-thumb-md {
  width: 100%;
  height: 120px;
  border-radius: 8px;
  overflow: hidden;
  background: #f7f8fb;
}

.media-thumb-md img {
  width: 100%;
  height: 100%;
  object-fit: cover;
}

.album-btns {
  margin-top: 8px;
  display: flex;
  gap: 6px;
  flex-wrap: wrap;
}

.call-record-query {
  display: flex;
  align-items: center;
  gap: 10px;
  margin-bottom: 12px;
}

.bill-summary {
  display: flex;
  align-items: stretch;
  gap: 10px;
  margin-bottom: 12px;
}

.bill-summary-card {
  min-width: 180px;
  border-radius: 8px;
  padding: 10px 12px;
  border: 1px solid #edf0f5;
  background: #fafbfc;
}

.bill-summary-card .label {
  color: #8b8f99;
  font-size: 12px;
  margin-bottom: 4px;
}

.bill-summary-card .value {
  color: #242933;
  font-size: 18px;
  font-weight: 700;
}

.bill-summary-card.income-coins {
  border-color: #d4efe1;
  background: #f3fbf6;
}

.bill-summary-card.income-diamonds {
  border-color: #d9e5f8;
  background: #f5f8ff;
}

.bill-summary-card.expense-coins {
  border-color: #f1d9d9;
  background: #fff6f6;
}

.bill-summary-card.expense-diamonds {
  border-color: #f3dfcc;
  background: #fff8f1;
}
</style>
