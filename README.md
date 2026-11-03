StudentDormitory · 学生公寓管理系统（Android）

一个纯本地的 Android 学生公寓管理系统：Java 8 + Room，双角色（学生 / 管理员）权限区分，
覆盖请假审批、报修、进出打卡、寝室评分、缴费管理、公告推送、访客登记等日常事务。

## 界面预览

<table>
<tr>
<td align="center" width="33%"><img src="docs/截图/11-student-home.png" width="230"><br><sub><b>学生首页</b> · 7 个功能入口</sub></td>
<td align="center" width="33%"><img src="docs/截图/12-leave-submit.png" width="230"><br><sub><b>请假上报</b> · 表单 + 本人记录与审批状态</sub></td>
<td align="center" width="33%"><img src="docs/截图/13-arrears.png" width="230"><br><sub><b>欠费查询</b> · 年费从 room_type 表读取</sub></td>
</tr>
<tr>
<td align="center"><img src="docs/截图/02-admin-home.png" width="230"><br><sub><b>管理员首页</b> · 7 个管理模块</sub></td>
<td align="center"><img src="docs/截图/03-leave-review.png" width="230"><br><sub><b>请假审批</b> · 待审核 / 已同意 / 已驳回</sub></td>
<td align="center"><img src="docs/截图/04-leave-reject.png" width="230"><br><sub><b>驳回</b> · 必须填写驳回原因</sub></td>
</tr>
<tr>
<td align="center"><img src="docs/截图/08-student-manage.png" width="230"><br><sub><b>宿舍管理</b> · 学生增删改查</sub></td>
<td align="center"><img src="docs/截图/05-repair-handle.png" width="230"><br><sub><b>报修处理</b> · 一键标记已修</sub></td>
<td align="center"><img src="docs/截图/19-admin-pay.png" width="230"><br><sub><b>缴费管理</b> · 登记欠费 + 查看记录</sub></td>
</tr>
</table>

> 全部 18 张截图见 [`docs/截图/`](docs/截图/)

## 这个项目的重点

功能是课程设计的常规范围，技术价值在于**两次重构**：

**第一次：把散落的手写 SQL 收敛成分层架构**

| | 改造前 | 改造后 |
|---|---|---|
| 数据访问 | 每个页面自己 new Helper、自己拼 SQL、自己解析 Cursor | 8 个 DAO 统一负责，外部只看得见 Bean |
| 列取值 | `cursor.getInt(0)` 列位置硬编码，89 处 | `getColumnIndexOrThrow("列名")` |
| 同一段映射 | 在 5 个文件里各抄一遍 | 只此一份 |
| 资源释放 | 13 处 Cursor 不关闭 | `try { ... } finally { close(); }` |
| 级联删除 | 无事务，可能半删 | `beginTransaction` + `setTransactionSuccessful` |

**第二次：把手写 DAO 换成 Room**

| | 手写 DAO | Room |
|---|---|---|
| 建表 | 手写 `create table` 字符串 | 由 `@Entity` 生成，**SQL 与 Java 字段不可能对不上** |
| SQL 写错 | 运行时才炸 | **编译期报错**（Room 把每条 SQL 拿到内存 SQLite 上真跑） |
| 事务 | 三件套 | 一个 `@Transaction` 注解 |
| 联表结果 | 往实体里塞"有时有值"的字段 | `@Embedded` + 独立的联表 POJO |

同时修复 30+ 处缺陷，含 6 个必崩问题（空指针、`String.format` 误用、
`NumberFormatException`、废弃 Fragment 在 API 21 上崩溃）。

## 技术栈

| 项 | 版本 / 说明 |
|---|---|
| 语言 | Java 8 |
| 存储 | **Room 2.4.3**（9 张表，`AppDatabase` version 8，WAL 模式） |
| UI | RecyclerView + ViewBinding + 自定义 Adapter/ViewHolder |
| 第三方 | Glide（图片）、PictureSelector（相册选图） |
| 构建 | Gradle 8.9 · AGP 8.7.3 · **JDK 17** |
| SDK | compileSdk 32 / targetSdk 33 / **minSdk 21** |
| 规模 | 66 个 Java 文件，约 6700 行；41 个布局 |

> ⚠️ `compileSdk` 是 32，所以 Room 只能用 **2.4.x**（2.5+ 要求 compileSdk 33）。
> 这个限制导致用不了 `:#{#param.field}` 参数展开语法，详见 `docs/学习-15`。

## 构建

    $env:JAVA_HOME = "C:\path\to\jdk-17"
    .\gradlew.bat clean assembleDebug --no-daemon --console=plain

产物：`app/build/outputs/apk/debug/app-debug.apk`

> ⚠️ Gradle 8.9 需要 **JDK 17**。JDK 21+ 跑不起来。

用 Android Studio 打开：`File → Open` 选**本项目根目录**，
再把 `Settings → Build → Build Tools → Gradle → Gradle JDK` 设为 17。

`local.properties` 需指向本机 Android SDK（此文件不入库）：

    sdk.dir=C\:\\Users\\<你>\\AppData\\Local\\Android\\Sdk

## 内置账号

管理员 `admin` / `123`（首次建库由 `AppDatabase` 的种子回调创建）。
学生账号在登录页自行注册。

## 结构

    app/src/main/java/com/example/studentdormitory/
    ├── bean/      (11)  8 个 @Entity + RoomType + 3 个联表 POJO
    ├── enums/      (3)  角色 / 进出类型 / 报修状态
    ├── dao/        (9)  Room @Dao 接口：只有 SQL 与签名，没有一行 Java 逻辑
    ├── db/         (1)  AppDatabase：注册实体、单例、种子数据回调
    ├── adapter/    (9)  RecyclerView 适配器
    ├── util/       (4)  SharedPreferences / 键盘 / Glide 引擎
    ├── widget/     (1)  自定义 ActionBar
    └── ui/
        ├── activity/ (28)
        └── fragment/  (4)  已迁移到 androidx.fragment.app.Fragment

数据层：`user` · `repairs` · `temperature` · `come` · `score` · `task` · `pay` · `fang` · `room_type`

> `temperature` 表的语义已改为**请假**——列名保留但存的是请假原因，另带 `status`
> （0待审核/1已同意/2已驳回）与 `rejectReason`。

## 文档

- [`docs/接手说明.md`](docs/接手说明.md) —— 项目定位、数据层关系、界面地图、已知缺陷分级清单
- [`docs/学习-*.md`](docs/) —— 16 篇源码学习笔记（登录流程、对象与引用、Git 原理、
  SQLite 列亲和性、手写 DAO 分层、手写 DAO 迁移到 Room 等）
- [`docs/作品包/`](docs/作品包/) —— 投递用项目说明与运行说明
- [`docs/面试速览.md`](docs/面试速览.md) —— 一页速览：做了什么、难点在哪、哪些是已知不足

> 注：`docs/学习-*` 是开发过程中同步写的学习笔记，文中出现的提交哈希来自本地开发历史。
> 本仓库公开发布时压成了单个提交，所以 `git log` 里看不到那些哈希——不影响阅读，
> 笔记本身讲的是概念，哈希只是当时的实例。

## 与服务端打通（网络层）

本项目**已经能调用配套的 Spring Boot 后端**，不再只是本地单机。

入口：「我的」→「在线学生列表（后端接口）」

| 能力 | 实现 |
|---|---|
| HTTP 客户端 | Retrofit 2.9 + OkHttp 4.12（`okhttp-bom` 锁版本，避免与 retrofit 自带的 3.14 冲突） |
| JSON 转换 | Gson（DTO 字段名必须与后端返回的 key 完全一致） |
| 请求日志 | `HttpLoggingInterceptor`（Logcat 过滤 tag `OkHttp`，能看到实际 URL 与请求/响应 JSON） |
| 调用方式 | **`enqueue` 异步回调**——网络请求放主线程会抛 `NetworkOnMainThreadException` |

```
app/src/main/java/com/example/studentdormitory/net/
├── ApiClient.java      Retrofit 单例 + BASE_URL（模拟器 10.0.2.2 / 真机局域网 IP）
├── ApiService.java     接口声明（无实现类，Retrofit 动态代理生成）
└── dto/                与后端一一对应的数据结构
```

**三层失败要分清**（这是网络开发最核心的认知）：

| 层 | 表现 | 原因 |
|---|---|---|
| 传输层 | `onFailure`：`ConnectException` / `SocketTimeout` | 后端没启动、IP 不对、不在同一网段 |
| HTTP 层 | `response.isSuccessful() == false` | 4xx / 5xx |
| 业务层 | `response.body().getCode() != 0` | 后端主动返回的错误（参数、权限、数据库） |

> 后端仓库：`C:\AndroidProjects\DormitoryServer`（Spring Boot 3 + MyBatis + MySQL）

## 测试

目前有一条**不需要模拟器**的单元测试：

```
.\gradlew.bat testDebugUnitTest
```

`NetMappingTest`（3 个用例）用**从真实后端抓下来的 JSON** 验证 DTO 字段映射——
Gson 按字段名反射填充，**写错一个字母那个字段就是 null 且不报错**，
所以这条测试守的是"客户端 DTO 与后端返回格式"这个契约。

## 已知边界

- **存量页面未收敛**：新增的联调页已按「服务端权威 + 本地缓存」实现
  （`StudentRepository`：网络优先 → 成功则整体覆盖缓存 → 失败才回退，界面标注数据来源），
  但存量 20+ 页面仍是纯本地读取，尚未统一到 Repository
- 密码明文存储，未做加盐哈希
- 只有网络层的 JSON 映射测试，UI 与数据库层仍无自动化测试
- **数据库操作全在主线程**：Room 默认禁止这么做，本项目用 `allowMainThreadQueries()` 放开了。
  这是有意的取舍（改成异步要重写每个页面的数据流），但仍是技术债
- **数据库升级**：v8→v9 已写精确 `Migration`（只加缓存表、不动老数据）；
  但 v7→v8 那一步仍依赖 `fallbackToDestructiveMigration()`（旧库非 Room 建，无法忠实迁移）
- 后端无鉴权：接口裸奔，没有登录 / token

## 许可

课程设计延伸项目，用于教学与技术展示。
