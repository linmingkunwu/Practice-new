/*
 * test-core.mjs — 自测脚本（Node 18+）
 * 运行：node test-core.mjs
 * 校验条码核心算法与已知例子，全部通过时退出码为 0。
 */
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const B = require('./barcode-core.js');

let total = 0;
let failed = 0;

function eq(name, actual, expected) {
  total++;
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  if (a === e) return;
  failed++;
  console.log(`✗ ${name}\n    期望: ${e}\n    实际: ${a}`);
}
function ok(name, cond) {
  total++;
  if (cond) return;
  failed++;
  console.log(`✗ ${name}`);
}

/* ---------------- 1. 权重方向 ---------------- */
eq('权重-12位数据', B.weights(12), [1, 3, 1, 3, 1, 3, 1, 3, 1, 3, 1, 3]);
eq('权重-11位数据', B.weights(11), [3, 1, 3, 1, 3, 1, 3, 1, 3, 1, 3]);
eq('权重-7位数据', B.weights(7), [3, 1, 3, 1, 3, 1, 3]);

/* ---------------- 2. 已知校验码 ---------------- */
eq('EAN-13 690123456789 → 2', B.calcCheck('690123456789').check, 2);
eq('EAN-13 400638133393 → 1', B.calcCheck('400638133393').check, 1);
eq('UPC-A 03600029145 → 2', B.calcCheck('03600029145').check, 2);
eq('EAN-8 9638507 → 4', B.calcCheck('9638507').check, 4);
eq('ITF-14 1001234500001 → 7', B.calcCheck('1001234500001').check, 7);
eq('SSCC-18 10614141123456789 → 7', B.calcCheck('10614141123456789').check, 7);
eq('GTIN-14 0690123456789 → 2', B.calcCheck('0690123456789').check, 2);

/* ---------------- 3. 完整码校验 ---------------- */
ok('EAN-13 6901234567892 正确', B.validate('EAN-13', '6901234567892').ok === true);
ok('EAN-13 6901234567891 错误', B.validate('EAN-13', '6901234567891').ok === false);
ok('UPC-A 036000291452 正确', B.validate('UPC-A', '036000291452').ok === true);
ok('EAN-8 96385074 正确', B.validate('EAN-8', '96385074').ok === true);
ok('ITF-14 10012345000017 正确', B.validate('ITF-14', '10012345000017').ok === true);
ok('ITF-14 06901234567892 正确', B.validate('ITF-14', '06901234567892').ok === true);
ok('SSCC-18 106141411234567897 正确', B.validate('SSCC-18', '106141411234567897').ok === true);
ok('EAN-13 位数错误能报错', B.validate('EAN-13', '690123456789').ok === false);
ok('UPC-A 系统码 2 也可校验', B.validate('UPC-A', '212345678905').error === '校验码错误：应为 9，实际 5');

/* ---------------- 4. UPC-E 展开（GS1 已知例） ---------------- */
const e1 = B.expandUPCE('04252614');
eq('UPC-E 04252614 → UPC-A', e1.upca, '042100005264');
eq('UPC-E 04252614 标记位', e1.marker, 1);
eq('UPC-E 04252614 厂商', e1.manufacturer, '42100');
eq('UPC-E 04252614 商品', e1.item, '00526');
eq('UPC-E 04252614 校验有效', e1.checkValid, true);

const e2 = B.expandUPCE('01234565');
eq('UPC-E 01234565 → UPC-A', e2.upca, '012345000065');
eq('UPC-E 01234565 标记位', e2.marker, 6);

const e3 = B.expandUPCE('01234531');
eq('UPC-E 01234531 → UPC-A (规则3)', e3.upca, '012300000451');

const e4 = B.expandUPCE('01234543');
eq('UPC-E 01234543 → UPC-A (规则4)', e4.upca, '012340000053');

ok('UPC-E 系统码 2 非法', !!B.expandUPCE('21234565').error);

/* ---------------- 5. UPC-A → UPC-E 压缩 ---------------- */
const c1 = B.compressUPCA('042100005264');
eq('UPC-A 042100005264 → UPC-E', c1.upce, '04252614');
eq('压缩规则', c1.rule, '0/1/2');

const c2 = B.compressUPCA('012345000065');
eq('UPC-A 012345000065 → UPC-E', c2.upce, '01234565');
eq('压缩规则', c2.rule, '5~9');

const c3 = B.compressUPCA('012300000451');
eq('UPC-A 012300000451 → UPC-E', c3.upce, '01234531');
eq('压缩规则', c3.rule, '3');

const c4 = B.compressUPCA('012340000053');
eq('UPC-A 012340000053 → UPC-E', c4.upce, '01234543');
eq('压缩规则', c4.rule, '4');

ok('普通 UPC-A 036000291452 不可压缩', B.compressUPCA('036000291452').compressible === false);
ok('系统码 2 不可压缩', B.compressUPCA('212345678905').compressible === false);
ok('13 位不能当 UPC-A 压缩', B.compressUPCA('0690123456789').compressible === false);

/* ---------------- 6. 关键考点：UPC-E 校验码 ≠ 自身模 10 ---------------- */
eq('04252614 自身模10会算出 0（陷阱）', B.calcCheck('0425261').check, 0);
eq('04252614 的桥接校验码（UPC-A）', e1.check, 4);
ok('UPC-E 04252614 验码通过（用展开法）', B.validate('UPC-E', '04252614').ok === true);
ok('UPC-E 04252614 若按自身模10会被误判', B.validate('UPC-E', '04252610').ok === false);

/* ---------------- 7. 随机往返：可压缩 UPC-A → UPC-E → UPC-A ---------------- */
let seed = 20261021;
function rnd() { seed = (seed * 1103515245 + 12345) % 2147483648; return seed / 2147483648; }
function digit(n) { return Math.floor(rnd() * n); }
function dstr(n) { let s = ''; for (let i = 0; i < n; i++) s += String(digit(10)); return s; }

function makeUPCAByRule(rule) {
  const ns = String(digit(2)); // 0 或 1
  let m = '', p = '';
  if (rule === '0/1/2') {
    m = dstr(2) + String(digit(3)) + '00';
    p = '00' + dstr(3);
  } else if (rule === '3') {
    m = dstr(2) + String(3 + digit(7)) + '00';
    p = '000' + dstr(2);
  } else if (rule === '4') {
    m = dstr(3) + String(1 + digit(9)) + '0';
    p = '0000' + dstr(1);
  } else {
    m = dstr(4) + String(1 + digit(9));
    p = '0000' + String(5 + digit(5));
  }
  const data11 = ns + m + p;
  return data11 + B.calcCheck(data11).check;
}

for (const rule of ['0/1/2', '3', '4', '5~9']) {
  for (let i = 0; i < 300; i++) {
    const upca = makeUPCAByRule(rule);
    const c = B.compressUPCA(upca);
    if (!c.compressible) { eq(`随机 ${rule} 应可压缩 ${upca}`, false, true); continue; }
    const ex = B.expandUPCE(c.upce);
    if (ex.upca !== upca) eq(`往返 ${rule}`, ex.upca, upca);
    total++;
  }
}

/* 随机任意 UPC-A：不可压缩时必须给出原因，不能抛错 */
for (let i = 0; i < 300; i++) {
  const data11 = dstr(11);
  const upca = data11 + B.calcCheck(data11).check;
  const c = B.compressUPCA(upca);
  if (!c.compressible) {
    total++;
    if (!c.reason) { failed++; console.log(`✗ 不可压缩时缺少原因: ${upca}`); }
  } else {
    const ex = B.expandUPCE(c.upce);
    eq(`随机任意码往返 ${upca}`, ex.upca, upca);
  }
}

/* ---------------- 8. inspect / structure ---------------- */
const ins = B.inspect('EAN-13', '690123456789');
eq('inspect 数据位模式', ins.mode, 'data');
eq('inspect 自动补校验', ins.result.full, '6901234567892');
const ins2 = B.inspect('UPC-A', '036 000 291 452');
eq('inspect 忽略空格', ins2.mode, 'full');
ok('inspect 忽略空格后验码通过', ins2.result.ok === true);
const ins3 = B.inspect('EAN-8', '96385074');
eq('inspect EAN-8 完整码', ins3.mode, 'full');
const st = B.structure('EAN-13', '6901234567892');
eq('结构分段数', st.length, 3);
eq('结构-前缀', st[0].text, '690');
eq('结构-校验位', st[2].text, '2');
eq('前缀查询 690', B.prefixInfo('6901234567892').region, '中国');

/* ---------------- 9. 随机生成（练习器用） ---------------- */
for (let i = 0; i < 200; i++) {
  for (const type of ['EAN-13', 'UPC-A', 'EAN-8', 'UPC-E', 'ITF-14', 'SSCC-18']) {
    const code = B.randomCode(type);
    total++;
    if (B.validate(type, code).ok !== true) {
      failed++;
      console.log(`✗ randomCode(${type}) 生成了非法码: ${code}`);
    }
    const bad = B.randomWrongCheck(type);
    total++;
    if (B.validate(type, bad).ok !== false) {
      failed++;
      console.log(`✗ randomWrongCheck(${type}) 生成了合法码: ${bad}`);
    }
  }
}
for (let i = 0; i < 200; i++) {
  const r = B.randomCompressibleUPCA();
  total++;
  if (B.validate('UPC-A', r.upca).ok !== true) { failed++; console.log(`✗ randomCompressibleUPCA 非法: ${r.upca}`); }
  total++;
  if (B.expandUPCE(r.upce).upca !== r.upca) { failed++; console.log(`✗ randomCompressibleUPCA 往返失败: ${r.upca} / ${r.upce}`); }
}

/* ---------------- 结果 ---------------- */
if (failed === 0) {
  console.log(`✅ 全部通过：${total} 项断言`);
  process.exit(0);
} else {
  console.log(`❌ 失败 ${failed} / ${total} 项`);
  process.exit(1);
}
