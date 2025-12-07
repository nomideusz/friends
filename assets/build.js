const esbuild = require('esbuild')
const sveltePlugin = require('esbuild-svelte')
const sveltePreprocess = require('svelte-preprocess')
const path = require('path')

const args = process.argv.slice(2)
const watch = args.includes('--watch')
const deploy = args.includes('--deploy')

const loader = {
  '.ttf': 'file',
  '.woff': 'file',
  '.woff2': 'file',
  '.eot': 'file',
  '.svg': 'file',
}

const plugins = [
  sveltePlugin({
    preprocess: sveltePreprocess(),
    compilerOptions: { css: 'injected' }
  })
]

let opts = {
  entryPoints: ['js/app.js'],
  bundle: true,
  target: 'es2020',
  outdir: '../priv/static/assets',
  logLevel: 'info',
  loader,
  plugins,
  external: ['/fonts/*', '/images/*'],
  nodePaths: [path.resolve(__dirname, 'node_modules')]
}

if (deploy) {
  opts = {
    ...opts,
    minify: true
  }
}

if (watch) {
  opts = {
    ...opts,
    sourcemap: 'inline'
  }
  esbuild.context(opts).then(ctx => {
    ctx.watch()
  }).catch(() => process.exit(1))
} else {
  esbuild.build(opts).catch(() => process.exit(1))
}

