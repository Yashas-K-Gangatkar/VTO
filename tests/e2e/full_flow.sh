#!/usr/bin/env bash
# End-to-end flow test for VTO platform
# Runs: push SKU → generate QR → mint token → create body → QR scan try-on → poll status
set -euo pipefail

API_GATEWAY="http://localhost:8080"
RETAILER_ID="00000000-0000-0000-0000-000000000001"
TEST_SKU="E2E-TEST-SKU-$(date +%s)"
SHOPPER_ID="e2e-shopper-$(date +%s)"
API_KEY="vto_dev_bypass_key_for_e2e_testing_only"

echo "============================================================"
echo "VTO End-to-End Flow Test"
echo "============================================================"
echo "Test SKU:    $TEST_SKU"
echo "Shopper ID:  $SHOPPER_ID"
echo ""

echo "==> [1/7] Verifying services are up..."
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

echo "==> [2/7] Pushing test SKU to catalog..."
PUSH_RESPONSE=$(curl -fsS -X POST "$API_GATEWAY/v1/catalog/skus" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"sku\":\"$TEST_SKU\",\"name\":\"E2E Test Dress\",\"category\":\"dress\",\"gender\":\"women\",\"color\":\"black\",\"fabric\":\"cotton\",\"image_urls\":[\"https://example.com/test.jpg\"]}") || { echo "    FAIL"; exit 1; }
echo "    OK SKU pushed"
echo ""

echo "==> [3/7] Generating QR code for SKU..."
QR_RESPONSE=$(curl -fsS -X POST "$API_GATEWAY/v1/qr-codes" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"sku\":\"$TEST_SKU\"}") || { echo "    FAIL"; exit 1; }
QR_PAYLOAD=$(echo $QR_RESPONSE | jq -r '.data.payload')
echo "    OK QR payload: ${QR_PAYLOAD:0:50}..."
echo ""

echo "==> [4/7] Minting shopper token..."
TOKEN_RESPONSE=$(curl -fsS -X POST "$API_GATEWAY/v1/tokens" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"shopper_id\":\"$SHOPPER_ID\",\"scopes\":[\"body_scan\",\"tryon\",\"events\"]}") || { echo "    FAIL"; exit 1; }
SHOPPER_TOKEN=$(echo $TOKEN_RESPONSE | jq -r '.data.access_token')
echo "    OK Shopper token minted"
echo ""

echo "==> [5/7] Creating body profile..."
echo "fake-scan-data" > /tmp/vto-test-scan.dat
BODY_RESPONSE=$(curl -fsS -X POST "$API_GATEWAY/v1/body_profiles" \
  -H "Authorization: Bearer $SHOPPER_TOKEN" \
  -F "scan_data=@/tmp/vto-test-scan.dat" \
  -F 'metadata={"scan_device":"iphone_pro_lidar","scan_quality_score":0.92,"measurements":{"chest_cm":96.2,"waist_cm":78.5,"hip_cm":102.1,"inseam_cm":81.0,"height_cm":175.0}}') || { echo "    FAIL"; exit 1; }
BODY_PROFILE_ID=$(echo $BODY_RESPONSE | jq -r '.data.id')
echo "    OK Body profile: $BODY_PROFILE_ID"
echo ""

echo "==> [6/7] Creating try-on via QR scan..."
TRYON_RESPONSE=$(curl -fsS -X POST "$API_GATEWAY/v1/tryons/qr-scan" \
  -H "Authorization: Bearer $SHOPPER_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"qr_payload\":\"$QR_PAYLOAD\",\"body_profile_id\":\"$BODY_PROFILE_ID\",\"size\":\"M\",\"view\":\"front\"}") || { echo "    FAIL"; exit 1; }
TRYON_ID=$(echo $TRYON_RESPONSE | jq -r '.data.tryon_id')
echo "    OK Try-on created: $TRYON_ID"
echo ""

echo "==> [7/7] Polling for try-on completion..."
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
    exit 1
  fi
  sleep 2
done
echo "    FAIL Try-on timed out"
exit 1
