/*
 * barcode-core.js — 商品条码核心算法（无依赖，浏览器 / Node 通用）
 * 覆盖：EAN-13、UPC-A、EAN-8、UPC-E、ITF-14、SSCC-18
 * 内容：模 10 校验码计算与验码、UPC-A → UPC-E 消零压缩、UPC-E → UPC-A 展开、码段结构
 *
 * 浏览器：<script src="barcode-core.js"></script>  之后用 window.BarcodeCore
 * Node：  vm.runInThisContext(fs.readFileSync('barcode-core.js','utf8')) 之后用 globalThis.BarcodeCore
 *
 * 算法要点（与 GS1 / ISO-IEC 15420 一致）：
 *   校验码：从最右边的数据位开始，权重 3、1、3、1… 交替；
 *           总和 S；校验码 C = (10 − S mod 10) mod 10。校验位本身不参加计算。
 *   UPC-E：UPC-A（系统码 0/1）中零的分布符合 4 类规则之一时才能压缩；
 *           UPC-E 的校验码 = 压缩前 UPC-A 的校验码（不是对 8 位 UPC-E 自己算）。
 */
(function (root) {
  'use strict';

  /* 码制定义：len = 含校验位的总位数，dataLen = 数据位数 */
  var MODELS = {
    'EAN-13':  { len: 13, dataLen: 12, name: 'EAN-13',  short: 'EAN-13',  note: '商品条码（中国：690~699 开头）' },
    'UPC-A':   { len: 12, dataLen: 11, name: 'UPC-A',   short: 'UPC-A',   note: '北美商品条码（GTIN-12）' },
    'EAN-8':   { len: 8,  dataLen: 7,  name: 'EAN-8',   short: 'EAN-8',   note: '缩短版商品条码（GTIN-8，不是压缩码）' },
    'UPC-E':   { len: 8,  dataLen: 7,  name: 'UPC-E',   short: 'UPC-E',   note: 'UPC-A 的消零压缩码（8 位）' },
    'ITF-14':  { len: 14, dataLen: 13, name: 'ITF-14',  short: 'ITF-14',  note: '箱码 / 包装代码（GTIN-14）' },
    'SSCC-18': { len: 18, dataLen: 17, name: 'SSCC-18', short: 'SSCC-18', note: '物流单元序列代码（18 位）' }
  };

  /* 常见 GS1 前缀（前 3 位）→ 国家 / 地区。仅用于展示，完整表见 GS1 前缀码表。 */
  var GS1_PREFIX = {
    '000': '美国/加拿大', '001': '美国/加拿大', '006': '美国/加拿大', '012': '美国/加拿大',
    '300': '法国', '301': '法国', '350': '法国',
    '400': '德国', '440': '德国',
    '450': '日本', '490': '日本', '499': '日本',
    '471': '中国台湾', '489': '中国香港', '958': '中国澳门',
    '690': '中国', '691': '中国', '692': '中国', '693': '中国',
    '694': '中国', '695': '中国', '696': '中国', '697': '中国', '698': '中国', '699': '中国',
    '880': '韩国', '885': '泰国', '888': '新加坡', '890': '印度', '899': '印度尼西亚',
    '930': '澳大利亚', '940': '新西兰', '955': '马来西亚', '539': '爱尔兰',
    '500': '英国', '501': '英国', '520': '希腊', '560': '葡萄牙', '570': '丹麦',
    '750': '墨西哥', '789': '巴西', '800': '意大利', '840': '西班牙',
    '870': '荷兰', '900': '奥地利', '910': '奥地利'
  };

  function onlyDigits(s) {
    return typeof s === 'string' && /^[0-9]+$/.test(s);
  }

  function clean(input) {
    return String(input == null ? '' : input).replace(/[\s\-－—]/g, '');
  }

  /* 数据位权重：保证最右边数据位权重为 3，向左 1、3 交替 */
  function weights(n) {
    var arr = [], w = (n % 2 === 0) ? 1 : 3; // 最左权重：数据位偶数个从 1 起，奇数个从 3 起
    for (var i = 0; i < n; i++) { arr.push(w); w = 4 - w; }
    return arr;
  }

  /* 计算校验码：data 为不含校验位的数据位字符串 */
  function calcCheck(data) {
    var s = clean(data);
    if (!onlyDigits(s)) throw new Error('数据位只能包含数字');
    var w = weights(s.length), steps = [], sum = 0;
    for (var i = 0; i < s.length; i++) {
      var d = Number(s.charAt(i));
      steps.push({ pos: i + 1, digit: d, weight: w[i], product: d * w[i] });
      sum += d * w[i];
    }
    var check = (10 - (sum % 10)) % 10;
    return {
      data: s,
      steps: steps,
      sum: sum,
      mod: sum % 10,
      check: check,
      full: s + check,
      formula: '(10 − ' + sum + ' mod 10) mod 10 = ' + check
    };
  }

  /* 解析完整码的码段（用于展示，不校验） */
  function structure(type, code) {
    code = clean(code);
    switch (type) {
      case 'EAN-13':
        return [
          { label: '前缀码', text: code.slice(0, 3), tip: '国别/地区（中国 690~699）' },
          { label: '厂商识别代码 + 商品项目代码', text: code.slice(3, 12), tip: '由编码中心分配，长度可变' },
          { label: '校验码', text: code.slice(12), tip: '模 10 计算' }
        ];
      case 'UPC-A':
        return [
          { label: '系统码', text: code.slice(0, 1), tip: '0/1 常规零售' },
          { label: '厂商代码', text: code.slice(1, 6), tip: '5 位' },
          { label: '商品代码', text: code.slice(6, 11), tip: '5 位' },
          { label: '校验码', text: code.slice(11), tip: '模 10' }
        ];
      case 'EAN-8':
        return [
          { label: '前缀码', text: code.slice(0, 3), tip: '国别/地区（通常 2~3 位）' },
          { label: '商品项目代码', text: code.slice(3, 7), tip: '编码中心分配' },
          { label: '校验码', text: code.slice(7), tip: '模 10' }
        ];
      case 'UPC-E':
        return [
          { label: '系统码', text: code.slice(0, 1), tip: '只能是 0 或 1' },
          { label: '压缩数据', text: code.slice(1, 7), tip: '第 6 位是“消零规则标记位”' },
          { label: '校验码', text: code.slice(7), tip: '沿用 UPC-A 的校验码' }
        ];
      case 'ITF-14':
        return [
          { label: '包装指示符', text: code.slice(0, 1), tip: '0~8 定量包装；9 变量' },
          { label: '厂商识别代码 + 商品项目代码', text: code.slice(1, 13), tip: 'GTIN-13 的 12 位数据' },
          { label: '校验码', text: code.slice(13), tip: '模 10（与 EAN 相同）' }
        ];
      case 'SSCC-18':
        return [
          { label: '扩展位', text: code.slice(0, 1), tip: '0~9 物流单元类型' },
          { label: '厂商识别代码 + 序列号', text: code.slice(1, 17), tip: '16 位' },
          { label: '校验码', text: code.slice(17), tip: '模 10' }
        ];
      default:
        return [];
    }
  }

  /* 常见 GS1 前缀查询 */
  function prefixInfo(code) {
    code = clean(code);
    var p = code.slice(0, 3);
    return { prefix: p, region: GS1_PREFIX[p] || '' };
  }

  /* UPC-E → UPC-A 展开。
     code8 = 8 位（系统码 + 6 位压缩数据 + 校验），也接受 7 位（系统码 + 6 位数据，自动算校验）。
     返回 { upca, check, checkValid, marker, manufacturer, item, rule, ruleText, error } */
  function expandUPCE(code8) {
    var s = clean(code8);
    if (!onlyDigits(s)) return { error: '只能包含数字' };
    if (s.length !== 8 && s.length !== 7) return { error: 'UPC-E 应为 8 位（或 7 位数据位）' };
    var ns = s.charAt(0);
    if (ns !== '0' && ns !== '1') return { error: 'UPC-E 的系统码只能是 0 或 1' };
    var data = s.slice(1, 7);
    var marker = Number(data.charAt(5));
    var mfr, item, rule, ruleText;

    if (marker <= 2) {
      mfr = data.charAt(0) + data.charAt(1) + data.charAt(5) + '00';
      item = '00' + data.charAt(2) + data.charAt(3) + data.charAt(4);
      rule = '0/1/2';
      ruleText = '标记位 0/1/2：厂商代码 = 前 2 位 + 标记位 + 00，商品代码 = 00 + 中间 3 位';
    } else if (marker === 3) {
      mfr = data.charAt(0) + data.charAt(1) + data.charAt(2) + '00';
      item = '000' + data.charAt(3) + data.charAt(4);
      rule = '3';
      ruleText = '标记位 3：厂商代码 = 前 3 位 + 00，商品代码 = 000 + 后 2 位';
    } else if (marker === 4) {
      mfr = data.slice(0, 4) + '0';
      item = '0000' + data.charAt(4);
      rule = '4';
      ruleText = '标记位 4：厂商代码 = 前 4 位 + 0，商品代码 = 0000 + 第 5 位';
    } else {
      mfr = data.slice(0, 5);
      item = '0000' + data.charAt(5);
      rule = '5~9';
      ruleText = '标记位 5~9：厂商代码 = 前 5 位，商品代码 = 0000 + 标记位';
    }

    var upcaData = ns + mfr + item;          // 11 位数据
    var c = calcCheck(upcaData);
    var check = c.check;
    var checkValid = s.length === 8 ? (Number(s.charAt(7)) === check) : null;
    return {
      upcaData: upcaData,
      upca: upcaData + check,
      check: check,
      checkValid: checkValid,
      carriedCheck: s.length === 8 ? Number(s.charAt(7)) : null,
      marker: marker,
      manufacturer: mfr,
      item: item,
      rule: rule,
      ruleText: ruleText,
      calc: c,
      error: null
    };
  }

  /* UPC-A → UPC-E 消零压缩（给定完整 12 位，或 11 位数据自动算校验）
     返回 { compressible, upce, rule, ruleText, reason, upca, check, calc } */
  function compressUPCA(code12) {
    var s = clean(code12);
    if (!onlyDigits(s)) return { compressible: false, reason: '只能包含数字' };
    if (s.length !== 12 && s.length !== 11) return { compressible: false, reason: 'UPC-A 应为 12 位（或 11 位数据位）' };
    var data11 = s.slice(0, 11);
    var c = calcCheck(data11);
    var upca = data11 + c.check;
    var ns = data11.charAt(0);
    if (ns !== '0' && ns !== '1') {
      return { compressible: false, reason: '系统码为 ' + ns + '，不是 0 或 1，不能压缩成 UPC-E', upca: upca, check: c.check, calc: c };
    }
    var m = data11.slice(1, 6);   // 厂商代码 5 位 m[0..4]
    var p = data11.slice(6, 11);  // 商品代码 5 位 p[0..4]
    var data6 = null, rule = '', ruleText = '';

    if (m.charAt(3) === '0' && m.charAt(4) === '0' && '012'.indexOf(m.charAt(2)) >= 0 && p.slice(0, 2) === '00') {
      rule = '0/1/2';
      data6 = m.charAt(0) + m.charAt(1) + p.charAt(2) + p.charAt(3) + p.charAt(4) + m.charAt(2);
      ruleText = '厂商代码第 3 位为 0/1/2 且第 4、5 位为 00，商品代码前 2 位为 00（商品 ≤ 00999）→ 保留厂商前 2 位 + 商品后 3 位 + 厂商第 3 位';
    } else if (m.charAt(3) === '0' && m.charAt(4) === '0' && p.slice(0, 3) === '000') {
      rule = '3';
      data6 = m.charAt(0) + m.charAt(1) + m.charAt(2) + p.charAt(3) + p.charAt(4) + '3';
      ruleText = '厂商代码末 2 位为 00（第 3 位为 3~9），商品代码前 3 位为 000（商品 ≤ 00099）→ 保留厂商前 3 位 + 商品后 2 位 + 标记位 3';
    } else if (m.charAt(4) === '0' && m.charAt(3) !== '0' && p.slice(0, 4) === '0000') {
      rule = '4';
      data6 = m.charAt(0) + m.charAt(1) + m.charAt(2) + m.charAt(3) + p.charAt(4) + '4';
      ruleText = '厂商代码末 1 位为 0（第 4 位非 0），商品代码前 4 位为 0000（商品 ≤ 00009）→ 保留厂商前 4 位 + 商品最后 1 位 + 标记位 4';
    } else if (m.charAt(4) !== '0' && p.slice(0, 4) === '0000' && '56789'.indexOf(p.charAt(4)) >= 0) {
      rule = '5~9';
      data6 = m + p.charAt(4);
      ruleText = '厂商代码末位非 0，商品代码为 00005~00009 → 厂商 5 位 + 商品最后 1 位（标记位 = 5~9）';
    }

    if (!data6) {
      return {
        compressible: false,
        reason: '零的分布不符合 4 类压缩规则（UPC-A 中至少要能按规则消去 4 个零），只能保留 UPC-A',
        upca: upca, check: c.check, calc: c
      };
    }
    return {
      compressible: true,
      upca: upca,
      upce: ns + data6 + c.check,
      data6: data6,
      check: c.check,
      rule: rule,
      ruleText: ruleText,
      calc: c
    };
  }

  /* 完整码校验：type 为码制；code 为含校验位的完整码 */
  function validate(type, code) {
    var model = MODELS[type];
    var s = clean(code);
    if (!model) return { ok: false, error: '未知码制：' + type };
    if (!onlyDigits(s)) return { ok: false, error: '只能包含数字' };
    if (s.length !== model.len) return { ok: false, error: type + ' 应为 ' + model.len + ' 位，当前 ' + s.length + ' 位' };

    if (type === 'UPC-E') {
      var ex = expandUPCE(s);
      if (ex.error) return { ok: false, error: ex.error };
      return {
        ok: ex.checkValid === true,
        type: type,
        actual: Number(s.charAt(7)),
        expected: ex.check,
        error: ex.checkValid === true ? null : '校验码错误：应为 ' + ex.check + '，实际 ' + s.charAt(7) + '（UPC-E 校验码 = 对应 UPC-A 的校验码）',
        upce: ex
      };
    }

    var data = s.slice(0, model.dataLen);
    var actual = Number(s.charAt(model.len - 1));
    var c = calcCheck(data);
    return {
      ok: actual === c.check,
      type: type,
      data: data,
      actual: actual,
      expected: c.check,
      error: actual === c.check ? null : '校验码错误：应为 ' + c.check + '，实际 ' + actual,
      calc: c
    };
  }

  /* 数据处理：输入位数可能是“数据位”或“完整码”，统一解析 */
  function inspect(type, input) {
    var model = MODELS[type];
    var s = clean(input);
    if (!model) return { error: '未知码制' };
    if (!onlyDigits(s)) return { mode: 'invalid', error: '只能输入数字（空格和横线会自动忽略）' };
    if (s.length > model.len) return { mode: 'invalid', error: type + ' 最多 ' + model.len + ' 位，当前 ' + s.length + ' 位' };
    if (s.length === model.len) {
      var v = validate(type, s);
      return { mode: 'full', input: s, result: v, model: model };
    }
    if (s.length === model.dataLen) {
      if (type === 'UPC-E') {
        var ex = expandUPCE(s);
        if (ex.error) return { mode: 'invalid', error: ex.error };
        return {
          mode: 'data', input: s, model: model,
          result: { ok: null, data: s, expected: ex.check, full: s + ex.check, upce: ex }
        };
      }
      var c = calcCheck(s);
      return { mode: 'data', input: s, model: model, result: { ok: null, data: s, expected: c.check, full: c.full, calc: c } };
    }
    return {
      mode: 'short', input: s, model: model,
      need: model.dataLen - s.length,
      error: '还需要 ' + (model.dataLen - s.length) + ' 位数据位（' + type + '：数据 ' + model.dataLen + ' 位 + 校验 1 位）'
    };
  }

  /* ---------------- 随机生成（供练习器使用，也可传入 rng 便于测试） ---------------- */
  function randInt(n, rng) { return Math.floor((rng || Math.random)() * n); }
  function randomDigits(n, rng) {
    var s = '';
    for (var i = 0; i < n; i++) s += String(randInt(10, rng));
    return s;
  }

  /* 生成一个“零结构符合压缩规则”的 UPC-A，返回 { upca, upce, rule } */
  function randomCompressibleUPCA(rng) {
    var rules = ['0/1/2', '3', '4', '5~9'];
    var rule = rules[randInt(rules.length, rng)];
    var ns = String(randInt(2, rng)); // 0 或 1
    var m = '', p = '';
    if (rule === '0/1/2') {
      m = randomDigits(2, rng) + String(randInt(3, rng)) + '00';
      p = '00' + randomDigits(3, rng);
    } else if (rule === '3') {
      m = randomDigits(2, rng) + String(3 + randInt(7, rng)) + '00';
      p = '000' + randomDigits(2, rng);
    } else if (rule === '4') {
      m = randomDigits(3, rng) + String(1 + randInt(9, rng)) + '0';
      p = '0000' + randomDigits(1, rng);
    } else {
      m = randomDigits(4, rng) + String(1 + randInt(9, rng));
      p = '0000' + String(5 + randInt(5, rng));
    }
    var data11 = ns + m + p;
    var upca = data11 + calcCheck(data11).check;
    var c = compressUPCA(upca);
    return { upca: upca, upce: c.upce, rule: c.rule };
  }

  /* 随机生成一个合法的完整码 */
  function randomCode(type, rng) {
    var model = MODELS[type];
    if (!model) throw new Error('未知码制：' + type);
    if (type === 'UPC-E') return randomCompressibleUPCA(rng).upce;
    var data;
    if (type === 'EAN-13') data = '690' + randomDigits(9, rng);
    else if (type === 'EAN-8') data = '690' + randomDigits(4, rng);
    else if (type === 'UPC-A') data = String(randInt(2, rng)) + randomDigits(10, rng);
    else data = randomDigits(model.dataLen, rng);
    return data + calcCheck(data).check;
  }

  /* 随机生成一个“校验码错误”的完整码 */
  function randomWrongCheck(type, rng) {
    var code = randomCode(type, rng);
    var last = Number(code.charAt(code.length - 1));
    var wrong = (last + 1 + randInt(9, rng)) % 10; // 保证与正确值不同
    return code.slice(0, -1) + wrong;
  }

  var api = {
    MODELS: MODELS,
    GS1_PREFIX: GS1_PREFIX,
    clean: clean,
    onlyDigits: onlyDigits,
    weights: weights,
    calcCheck: calcCheck,
    structure: structure,
    prefixInfo: prefixInfo,
    expandUPCE: expandUPCE,
    compressUPCA: compressUPCA,
    validate: validate,
    inspect: inspect,
    randomCompressibleUPCA: randomCompressibleUPCA,
    randomCode: randomCode,
    randomWrongCheck: randomWrongCheck
  };

  root.BarcodeCore = api;
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
})(typeof globalThis !== 'undefined' ? globalThis : this);
