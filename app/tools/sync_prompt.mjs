// 把项目唯一真源「框架文档」同步为应用资源，避免 Prompt 出现两份副本。
// 用法: node tools/sync_prompt.mjs
import fs from 'fs';
import path from 'path';

const SRC = path.resolve(process.cwd(), '../docs/解析理论框架_Prompt_v1.md');
const OUT = path.resolve(process.cwd(), 'assets/framework_prompt.md');

if (!fs.existsSync(SRC)) {
  console.error(`未找到框架文档: ${SRC}`);
  process.exit(1);
}
const doc = fs.readFileSync(SRC, 'utf8');

// 校验：装配所需的两个块必须存在（否则 App 启动即报错，早失败优于晚失败）
const sysBlock = doc.match(/```text\n([\s\S]*?)```/);
const schemaBlock = doc.match(/## 四、输出结构[\s\S]*?```json\n([\s\S]*?)```/);
if (!sysBlock) { console.error('框架文档缺少 ```text 的 System Prompt 块'); process.exit(1); }
if (!schemaBlock) { console.error('框架文档缺少第四节的 ```json Schema 块'); process.exit(1); }
if (!sysBlock[1].includes('第五部分：输出格式')) {
  console.error('System Prompt 缺少第五部分输出格式指令（v1.0.4 起必须包含）');
  process.exit(1);
}

fs.mkdirSync(path.dirname(OUT), { recursive: true });
fs.writeFileSync(OUT, doc);
const version = (doc.match(/当前版本 (v[\d.]+)/) || [])[1] || 'unknown';
console.log(`已同步 ${path.basename(OUT)}  <-  ${path.basename(SRC)}  (${version}, ${doc.length} 字符)`);
