const baseUrl = process.env.LOAD_BASE_URL || 'http://127.0.0.1:8080';
const stages = (process.env.LOAD_STAGES || '10,25,50,100').split(',').map(Number);
const requestsPerUser = Number(process.env.LOAD_REQUESTS_PER_USER || 5);
const maxErrorRate = Number(process.env.LOAD_MAX_ERROR_RATE || 0.01);
const maxP95Ms = Number(process.env.LOAD_MAX_P95_MS || 1000);

async function request(index) {
  const started = performance.now();
  try {
    const response = index % 2 === 0
      ? await fetch(`${baseUrl}/docs/openapi.json`)
      : await fetch(`${baseUrl}/ws`, {
          method: 'POST',
          headers: {'content-type': 'application/json'},
          body: JSON.stringify({query: 'query RampUp { musics { id title } }'}),
        });
    await response.arrayBuffer();
    return {ok: response.ok, ms: performance.now() - started, status: response.status};
  } catch (error) {
    return {ok: false, ms: performance.now() - started, error: String(error)};
  }
}

function percentile(values, fraction) {
  const sorted = [...values].sort((a, b) => a - b);
  return sorted[Math.min(sorted.length - 1, Math.ceil(sorted.length * fraction) - 1)] || 0;
}

async function stage(users) {
  const started = performance.now();
  const results = await Promise.all(
    Array.from({length: users}, async (_, user) => {
      const output = [];
      for (let requestIndex = 0; requestIndex < requestsPerUser; requestIndex += 1) {
        output.push(await request(user + requestIndex));
      }
      return output;
    }),
  );
  const flat = results.flat();
  const failures = flat.filter(result => !result.ok).length;
  const durationMs = performance.now() - started;
  return {
    users,
    requests: flat.length,
    durationMs: Math.round(durationMs),
    requestsPerSecond: Number((flat.length / (durationMs / 1000)).toFixed(1)),
    errors: failures,
    errorRate: Number((failures / flat.length).toFixed(4)),
    p50Ms: Math.round(percentile(flat.map(result => result.ms), 0.5)),
    p95Ms: Math.round(percentile(flat.map(result => result.ms), 0.95)),
    p99Ms: Math.round(percentile(flat.map(result => result.ms), 0.99)),
  };
}

(async () => {
  const report = {baseUrl, timestamp: new Date().toISOString(), requestsPerUser, stages: []};
  for (const users of stages) report.stages.push(await stage(users));
  console.log(JSON.stringify(report, null, 2));
  const failed = report.stages.some(item => item.errorRate > maxErrorRate || item.p95Ms > maxP95Ms);
  if (failed) process.exitCode = 1;
})();
