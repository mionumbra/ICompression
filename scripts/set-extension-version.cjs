'use strict';
// Update a temporary GameMaker project's extension only through ResourceTool MCP.
const fs = require('node:fs');
const path = require('node:path');
const readline = require('node:readline');
const { spawn, spawnSync } = require('node:child_process');

function parseArguments(args) {
  const allowed = new Set(['--project', '--version', '--resource-tool', '--project-tool', '--cache-dir']);
  const options = {};
  for (let i = 0; i < args.length; i += 2) {
    if (!allowed.has(args[i]) || !args[i + 1] || Object.hasOwn(options, args[i])) {
      throw new Error(`Invalid or duplicate argument: ${args[i]}`);
    }
    options[args[i]] = args[i + 1];
  }
  if (!options['--project'] || !options['--version']) throw new Error('--project and --version are required');
  const version = options['--version'];
  if (!/^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$/.test(version) ||
      version.split('.').some(part => part.length > 5 || Number(part) > 65535)) {
    throw new Error('Version must have four fields in the range 0..65535 without leading zeros');
  }
  for (const key of ['--project', '--resource-tool', '--project-tool', '--cache-dir']) {
    if (options[key]) options[key] = path.resolve(options[key]);
  }
  if (!fs.statSync(options['--project']).isFile()) throw new Error('Project file is missing');
  return options;
}

function resolveGmCli() {
  // npm's global bin directory normally contains node_modules; project-local
  // installs also work. Resolve the package bin and launch node without a shell.
  const searchPaths = [process.cwd(), __dirname, ...String(process.env.PATH || '').split(path.delimiter)];
  for (const base of searchPaths) {
    try {
      const manifest = require.resolve('@gamemaker/gm-cli/package.json', { paths: [base] });
      const metadata = JSON.parse(fs.readFileSync(manifest, 'utf8'));
      const relativeBin = typeof metadata.bin === 'string' ? metadata.bin : metadata.bin?.['gm-cli'];
      if (metadata.name !== '@gamemaker/gm-cli' || !relativeBin) continue;
      const packageRoot = path.dirname(manifest);
      const bin = path.resolve(packageRoot, relativeBin);
      if (path.relative(packageRoot, bin).startsWith('..') || !fs.statSync(bin).isFile()) continue;
      return bin;
    } catch { /* Try the next installed package location. */ }
  }
  throw new Error('Cannot resolve installed @gamemaker/gm-cli; install it locally/on PATH or pass --resource-tool');
}

function launch(options) {
  const project = options['--project'];
  const cache = options['--cache-dir'] || path.join(path.dirname(project), '.gmcache');
  let command;
  let args;
  if (options['--resource-tool']) {
    command = options['--resource-tool'];
    if (!fs.statSync(command).isFile()) throw new Error('ResourceTool executable is missing');
    args = ['mcp', `projectpath=${project}`];
    const projectTool = options['--project-tool'] ||
      path.join(cache, 'project-tool', 'node_modules', '@gm-tools', 'project-tool-win-x64', 'ProjectTool.exe');
    if (!fs.existsSync(projectTool)) throw new Error('ProjectTool is missing; pass --project-tool or use a populated --cache-dir');
    args.push(`projecttool=${projectTool}`, `prefabsfolder=${path.join(cache, 'prefabs')}`);
  } else {
    command = process.execPath;
    args = [resolveGmCli(), 'resourcetool', 'mcp', project, '--cache-dir', cache];
  }
  return spawn(command, args, { cwd: path.dirname(project), windowsHide: true, shell: false, stdio: ['pipe', 'pipe', 'pipe'] });
}

async function main() {
  const options = parseArguments(process.argv.slice(2));
  const extensionPath = path.join(path.dirname(options['--project']), 'extensions', 'ICompression', 'ICompression.yy');
  if (!fs.existsSync(extensionPath)) throw new Error('ICompression extension metadata is missing');
  const child = launch(options);
  let nextId = 0;
  let completed = false;
  let stderr = '';
  const pending = new Map();
  function rejectAll(error) {
    for (const { reject } of pending.values()) reject(error);
    pending.clear();
  }
  function stopTree() {
    if (!child.pid || child.exitCode !== null) return;
    if (process.platform === 'win32') {
      spawnSync(path.join(process.env.SystemRoot || 'C:\\Windows', 'System32', 'taskkill.exe'),
        ['/PID', String(child.pid), '/T', '/F'], { windowsHide: true, shell: false, stdio: 'ignore', timeout: 5000 });
    } else child.kill('SIGTERM');
  }
  const timeout = setTimeout(() => {
    rejectAll(new Error('ResourceTool MCP request timed out'));
    stopTree();
  }, 180000);
  child.stderr.on('data', chunk => { stderr = (stderr + chunk.toString()).slice(-8192); });
  child.on('error', error => rejectAll(error));
  child.on('exit', code => {
    if (!completed) rejectAll(new Error(`ResourceTool exited before completing (exit ${code})${stderr ? ': ' + stderr : ''}`));
  });
  child.stdin.on('error', error => rejectAll(error));
  readline.createInterface({ input: child.stdout }).on('line', line => {
    let response;
    try { response = JSON.parse(line); } catch { return; }
    const request = pending.get(response.id);
    if (!request) return;
    pending.delete(response.id);
    if (response.error) request.reject(new Error(`ResourceTool RPC error: ${JSON.stringify(response.error)}`));
    else request.resolve(response.result);
  });
  function send(method, params) {
    if (child.exitCode !== null) return Promise.reject(new Error('ResourceTool is not running'));
    return new Promise((resolve, reject) => {
      const id = ++nextId;
      pending.set(id, { resolve, reject });
      child.stdin.write(JSON.stringify({ jsonrpc: '2.0', id, method, params }) + '\n');
    });
  }
  try {
    await send('initialize', { protocolVersion: '2024-11-05', capabilities: {}, clientInfo: { name: 'ICompression-package-version', version: '1.0' } });
    child.stdin.write(JSON.stringify({ jsonrpc: '2.0', method: 'notifications/initialized' }) + '\n');
    const catalog = await send('tools/list', {});
    const setter = catalog?.tools?.find(tool => tool.name === 'resource_set');
    const schema = setter?.inputSchema;
    if (schema?.properties?.EXPR?.type !== 'string' || schema?.properties?.VALUE?.type !== 'string' ||
        !schema.required?.includes('EXPR') || !schema.required?.includes('VALUE')) {
      throw new Error('ResourceTool resource_set contract is unsupported');
    }
    const result = await send('tools/call', { name: 'resource_set', arguments: {
      EXPR: 'ICompression.extensionVersion', VALUE: options['--version']
    } });
    if (!result || result.isError) throw new Error(`ResourceTool rejected version update: ${JSON.stringify(result)}`);
    const text = fs.readFileSync(extensionPath, 'utf8');
    const matches = [...text.matchAll(/"extensionVersion"\s*:\s*"([^"]*)"/g)];
    if (matches.length !== 1 || matches[0][1] !== options['--version']) throw new Error('ResourceTool did not persist the requested extension version');
    completed = true;
    console.log(`Staged extension version: ${options['--version']}`);
  } finally {
    clearTimeout(timeout);
    child.stdin.end();
    stopTree();
  }
}

main().catch(error => { console.error(error.message); process.exitCode = 1; });
