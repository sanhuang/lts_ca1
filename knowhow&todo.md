## 領域知識

- 項目要求是從 ROS2 node 建立發送標準格式數據給 API
- API主要實作python.queue 一但接收node數據，則透過ws server發送給vue ws client接收
- vue接收了數據後持續不斷迴圈重複座標與路徑移動軌跡
- path_data.csv則是完全省略實體發送GPS訊號流程，模擬數據取得開始整個架構
