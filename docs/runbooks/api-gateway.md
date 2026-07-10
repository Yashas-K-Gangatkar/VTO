# Runbook: API Gateway

## Service overview

| Field | Value |
|-------|-------|
| Service name | api-gateway |
| Port | 8080 (local), 443 (production, behind ALB) |
| Repo path | `apps/api-gateway/` |
| Owner | Backend team |
| Dependencies | Redis (rate limiting), auth-service (JWKS), all upstream services |
| SLA | 99.9% (staging), 99.95% (production) |

## Common alerts

### `HighRateLimitRejections`
- **What:** >5% of requests getting 429
- **Cause:** Retailer hitting rate limit, or attack
- **Action:**
  1. Check Datadog: which retailer/IP is hitting?
  2. If legitimate retailer: consider raising their limit (dashboard or admin API)
  3. If attack: block IP in Cloudflare WAF
  4. If widespread: may indicate a downstream service is slow (causing retries)

### `HighLatencyP95`
- **What:** p95 latency >2s for `/v1/tryons` (poll)
- **Cause:** Upstream service slow, or network issue
- **Action:**
  1. Check Datadog service map: which upstream is slow?
  2. Check that service's runbook
  3. If tryon-service: check SQS queue depth, GPU pool health
  4. If widespread: post in #vto-incidents

### `RedisConnectionFailed`
- **What:** API Gateway cannot connect to Redis
- **Cause:** Redis failover, network partition, ElastiCache maintenance
- **Action:**
  1. Rate limiting is degraded — traffic will be allowed through without limits
  2. Check AWS console: ElastiCache event log
  3. If maintenance: wait it out (typically <60s)
  4. If real outage: failover to replica (automatic)

## Debugging

### Logs

```bash
# Local
docker logs vto-api-gateway -f

# Staging/prod
# Datadog Logs → service:api-gateway
```

### Health check

```bash
curl https://api.staging.vto.example/v1/health
# Expected: {"status":"ok","version":"...","timestamp":"..."}
```

### Reproduce a request

Every request has an `X-Request-Id` header. Search Datadog logs by that ID to see the full request lifecycle.

### Test rate limiting locally

```bash
# Hit /v1/health 1000 times rapidly
for i in $(seq 1 1000); do
  curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8080/v1/health
done | sort | uniq -c
# Expect to see 429s after exceeding RATE_LIMIT_DEFAULT
```

## Deployment

### Rolling deploy (ECS)

```bash
# Triggered automatically on merge to main (staging)
# Triggered on git tag for production (requires approval)

# Manual rollback
aws ecs update-service \
  --cluster vto-staging \
  --service api-gateway \
  --task-definition vto-api-gateway:PREVIOUS
```

### Verify deploy

```bash
# After deploy, verify version bumped
curl https://api.staging.vto.example/v1/health | jq .version
```

## On-call escalation

1. **First responder:** On-call engineer (PagerDuty schedule)
2. **If unresolved in 15 min:** Page secondary on-call
3. **If customer-impacting in 30 min:** Open #vto-incidents, notify Head of Eng
4. **If data breach suspected:** Notify CTO immediately; do NOT attempt remediation without CTO approval

## Post-incident

After any P0/P1 incident:
1. Fill out post-mortem template in `docs/runbooks/postmortems/`
2. Schedule review within 7 days
3. Action items tracked as issues with severity tag
