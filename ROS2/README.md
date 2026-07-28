# ROS 2 GNSS Publisher（模擬）

- `gps_publisher.py`：讀 `path_data.csv`，預設 **5Hz** 發佈 `NavSatFix` → `/gps/fix`
- 環境變數：`PUBLISH_RATE_HZ`、`GPS_CSV`、`ROS_TOPIC`、`ROS_DOMAIN_ID`

映像見 `../docker/Dockerfile.ros2`。
