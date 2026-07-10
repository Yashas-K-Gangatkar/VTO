from __future__ import annotations
from app.core.device import DeviceType, detect_device, get_device_info


class TestDeviceDetection:
    def test_detect_returns_valid_device(self):
        device = detect_device("auto")
        assert device in (DeviceType.CUDA, DeviceType.MPS, DeviceType.CPU)

    def test_detect_cpu(self):
        assert detect_device("cpu") == DeviceType.CPU

    def test_get_device_info_returns_dict(self):
        info = get_device_info(DeviceType.CPU)
        assert info["device"] == "cpu"
