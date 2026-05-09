import { defineStore } from 'pinia'
import { basicRoutes, vueModules } from '@/router/routes'
import api from '@/api'

const Layout = () => import('@/layout/index.vue')

// * 后端路由相关函数
// 根据后端传来数据构建出前端路由

function buildRoutes(routes = []) {
  const buildRouteName = (name, path, parentPath = '') => {
    const fullPath = parentPath ? `${parentPath}/${path}` : path
    const normalized = String(fullPath || '')
      .replace(/[:/]+/g, '_')
      .replace(/^_+|_+$/g, '')
    return normalized ? `${name}__${normalized}` : name
  }

  return routes.map((e) => {
    const route = {
      name: buildRouteName(e.name, e.path),
      path: e.path,
      component: Layout,
      isHidden: e.is_hidden,
      redirect: e.redirect,
      meta: {
        title: e.name,
        icon: e.icon,
        order: e.order,
        keepAlive: e.keepalive,
        alwaysShow: !!e?.remark?.alwaysShow,
      },
      children: [],
    }

    if (e.children && e.children.length > 0) {
      // 有子菜单
      route.children = e.children.map((e_child) => ({
        name: buildRouteName(e_child.name, e_child.path, e.path),
        path: e_child.path,
        component: vueModules[`/src/views${e_child.component}/index.vue`],
        isHidden: e_child.is_hidden,
        meta: {
          title: e_child.name,
          icon: e_child.icon,
          order: e_child.order,
          keepAlive: e_child.keepalive,
        },
      }))
    } else {
      // 没有子菜单，创建一个默认的子路由
      route.children.push({
        name: buildRouteName(`${e.name}Default`, 'default', e.path),
        path: '',
        component: vueModules[`/src/views${e.component}/index.vue`],
        isHidden: true,
        meta: {
          title: e.name,
          icon: e.icon,
          order: e.order,
          keepAlive: e.keepalive,
        },
      })
    }

    return route
  })
}

export const usePermissionStore = defineStore('permission', {
  state() {
    return {
      accessRoutes: [],
      accessApis: [],
    }
  },
  getters: {
    routes() {
      return basicRoutes.concat(this.accessRoutes)
    },
    menus() {
      return this.routes.filter((route) => route.name && !route.isHidden)
    },
    apis() {
      return this.accessApis
    },
  },
  actions: {
    async generateRoutes() {
      const res = await api.getUserMenu() // 调用接口获取后端传来的菜单路由
      this.accessRoutes = buildRoutes(res.data) // 处理成前端路由格式
      return this.accessRoutes
    },
    async getAccessApis() {
      const res = await api.getUserApi()
      this.accessApis = res.data
      return this.accessApis
    },
    resetPermission() {
      this.$reset()
    },
  },
})
