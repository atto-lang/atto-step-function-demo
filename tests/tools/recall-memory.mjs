#!/usr/bin/env node
import {JsonFileMemoryLedger} from '../reference/durable-memory.mjs';

const [file,tenantId,repo]=process.argv.slice(2);
if(!file||!tenantId||!repo) {
  console.error('Usage: node tests/tools/recall-memory.mjs FILE TENANT_ID REPO');
  process.exitCode=2;
} else {
  try {
    const ledger=await JsonFileMemoryLedger.open(file);
    const records=await ledger.recall({tenantId,repo});
    await ledger.close();
    console.log(JSON.stringify({tenantId,repo,records},null,2));
  } catch {
    console.error('READ_FAILED: invalid scope, missing data or corrupt checkpoint');
    process.exitCode=1;
  }
}
