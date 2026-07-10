#!/usr/bin/env bash
set -euo pipefail

API_GATEWAY="http://localhost:8080"
RETAILER_ID="00000000-0000-0000-0000-000000000001"
TEST_SKU="E2E-TEST-SKU-$(date +%s)"
SHOPPER_ID="e2e-shopper-$(date +%s)"

echo "============================================================"
echo "VTO End-to-End Flow Test"
echo "============================================================"
echo "Test SKU:    $TEST_SKU"
echo "Shopper ID:  $SHOPPER_ID"
echo ""

echo "==> [1/8] Verifying services are up..."
for svc in "api-gateway:8080" "auth-service:8081" "body-service:8082" "garment-service:8083" "tryon-service:8084"; do
  name=$(echo $svc | cut -d: -f1)
  port=$(echo $svc | cut -d: -f2)
  if curl -fsS "http://localhost:$port/health" > /dev/null 2>&1; then
    echo "    OK $name is up"
  else
    echo "    FAIL $name is down (port $port)"
    exit 1
  fi
done
echo ""

echo "==> [2/8] Bootstrapping API key..."
API_KEY_OUTPUT=$(docker exec vto-auth-service /create-api-key -retailer-id "$RETAILER_ID" -name "E2E Test Key" 2>&1) || {
  echo "    FAIL Could not create API key. Is auth-service running?"
  echo "    Output: $API_KEY_OUTPUT"
  exit 1
}
API_KEY=$(echo "$API_KEY_OUTPUT" | grep -E "^  vto_" | head -1 | awk '{print $1}')
if [ -z "$API_KEY" ]; then
  echo "    FAIL Could not extract API key from output"
  echo "    Output: $API_KEY_OUTPUT"
  exit 1
fi
echo "    OK API key created: ${API_KEY:0:12}..."
echo ""

echo "==> [3/8] Pushing test SKU to catalog..."
PUSH_RESPONSE=$(curl -fsS -X POST "$API_GATEWAY/v1/catalog/skus" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"sku\":\"$TEST_SKU\",\"name\":\"E2E Test Dress\",\"category\":\"dress\",\"gender\":\"women\",\"color\":\"black\",\"fabric\":\"cotton\",\"image_urls\":[\"https://example.com/test.jpg\"]}") || { echo "    FAIL"; exit 1; }
echo "    OK SKU pushed: $TEST_SKU"
echo ""

echo "==> [4/8] Generating QR code for SKU..."
QR_RESPONSE=$(curl -fsS -X POST "$API_GATEWAY/v1/qr-codes" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"sku\":\"$TEST_SKU\"}") || { echo "    FAIL"; exit 1; }
QR_PAYLOAD=$(echo $QR_RESPONSE | jq -r '.data.payload')
echo "    OK QR payload: ${QR_PAYLOAD:0:50}..."
echo ""

echo "==> [5/8] Minting shopper token..."
TOKEN_RESPONSE=$(curl -fsS -X POST "$API_GATEWAY/v1/tokens" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"shopper_id\":\"$SHOPPER_ID\",\"scopes\":[\"body_scan\",\"tryon\",\"events\"]}") || { echo "    FAIL"; exit 1; }
SHOPPER_TOKEN=$(echo $TOKEN_RESPONSE | jq -r '.data.access_token')
echo "    OK Shopper token minted"
echo ""

echo "==> [6/8] Creating body profile..."
echo "fake-scan-data-for-e2e-testing" > /tmp/vto-test-scan.dat
BODY_RESPONSE=$(curl -fsS -X POST "$API_GATEWAY/v1/body_profiles" \
  -H "Authorization: Bearer $SHOPPER_TOKEN" \
  -F "scan_data=@/tmp/vto-test-scan.dat" \
  -F 'metadata={"scan_device":"iphone_pro_lidar","scan_quality_score":0.92,"measurements":{"chest_cm":96.2,"waist_cm":78.5,"hip_cm":102.1,"inseam_cm":81.0,"height_cm":175.0}}') || { echo "    FAIL"; exit 1; }
BODY_PROFILE_ID=$(echo $BODY_RESPONSE | jq -r '.data.id')
echo "    OK Body profile created: $BODY_PROFILE_ID"
echo ""

echo "==> [7/8] Creating try-on via QR scan..."
TRYON_RESPONSE=$(curl -fsS -X POST "$API_GATEWAY/v1/tryons/qr-scan" \
  -H "Authorization: Bearer $SHOPPER_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"qr_payload\":\"$QR_PAYLOAD\",\"body_profile_id\":\"$BODY_PROFILE_ID\",\"size\":\"M\",\"view\":\"front\"}") || { echo "    FAIL"; exit 1; }
TRYON_ID=$(echo $TRYON_RESPONSE | jq -r '.data.tryon_id')
QR_SCAN_ID=$(echo $TRYON_RESPONSE | jq -r '.data.qr_scan_id')
echo "    OK Try-on created: $TRYON_ID"
echo "    QR scan ID: $QR_SCAN_ID"
echo ""

echo "==> [8/8] Polling for try-on completion..."
for i in $(seq 1 30); do
  STATUS_RESPONSE=$(curl -fsS "$API_GATEWAY/v1/tryons/$TRYON_ID" \
    -H "Authorization: Bearer $SHOPPER_TOKEN")
  STATUS=$(echo $STATUS_RESPONSE | jq -r '.data.status')
  echo "    Poll $i: status=$STATUS"

  if [ "$STATUS" = "succeeded" ]; then
    IMAGE_URL=$(echo $STATUS_RESPONSE | jq -r '.data.image_url')
    echo ""
    echo "============================================================"
    echo "SUCCESS: END-TO-END FLOW COMPLETED"
    echo "============================================================"
    echo "Try-On ID:  $TRYON_ID"
    echo "Image URL:  $IMAGE_URL"
    exit 0
  fi

  if [ "$STATUS" = "failed" ]; then
    echo "    FAIL Try-on failed"
    echo $STATUS_RESPONSE | jq '.data'
    exit 1
  fi

  sleep 2
done

echo "    FAIL Try-on timed out after 60 seconds"
exit 1
