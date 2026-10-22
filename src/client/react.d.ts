/**
 * 最小 React 类型声明（构建期只做类型检查，运行期由宿主 ModuleLoader 的
 * `require('react')` 提供真实的 React 18）。
 *
 * 为什么不装 `@types/react`：本包以 `github:` 源安装，pnpm 会在包里跑
 * `npm install` 取 devDependencies 再执行 `prepare`；多一个依赖就多一处
 * 版本漂移与下载失败面。client 侧只需要三个符号（createElement / useEffect /
 * useRef），声明在这里即可，产物经 tsdown `dts: false` 出包，不受影响。
 */
declare module 'react' {
  /** React ref 对象。 */
  export interface MutableRefObject<T> {
    current: T
  }

  /** 创建元素（无 JSX，纯 TS 用）。 */
  export function createElement(type: unknown, props?: unknown, ...children: unknown[]): unknown

  /** 副作用钩子；返回清理函数。 */
  export function useEffect(effect: () => void | (() => void), deps?: readonly unknown[]): void

  /** 引用钩子。 */
  export function useRef<T>(initial: T): MutableRefObject<T>
}
