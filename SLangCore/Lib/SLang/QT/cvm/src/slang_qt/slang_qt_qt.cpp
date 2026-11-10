/*
 * slang_qt_qt.cpp —— SLang QT 模块后端真实实现（C++ / Qt6 Widgets）
 * ==========================================================================
 * 实现 slang_qt_backend.h 声明的 slqt_be_*，把 SLang 句柄还原为真实 Qt
 * 对象并调用 Qt API；信号连接用 QObject::connect + lambda 捕获
 * (dispatchCb, slot)，发射时按信号类型调用 FFI 回调节流点重入 SLang VM
 * （与 cvm_webui_lib 的 trampoline 桥同思路）。
 *
 * 构建：见 slang_qt_qt.vcxproj（需 Qt6 Core/Widgets/Gui + msvc x64）。
 * 本文件不需要 moc（未定义任何 Q_OBJECT 子类，连接全用 lambda）。
 */

#include "slang_qt.h"
#include "slang_qt_backend.h"

#include <cstdio>
#include <cstring>
#include <cstdlib>

#ifdef _WIN32
#define NOMINMAX
#include <windows.h>
#endif

#include <QString>
#include <QStringList>
#include <QTimer>
#include <QEventLoop>
#include <QFile>
#include <QImage>
#include <QImageReader>
#include <QIcon>
#include <QPixmap>
#include <QPainter>
#include <QStyleFactory>
#include <QApplication>
#include <QWidget>
#include <QPushButton>
#include <QLabel>
#include <QLineEdit>
#include <QMainWindow>
#include <QVBoxLayout>
#include <QHBoxLayout>
#include <QGridLayout>
#include <QMessageBox>
#include <QTextEdit>
#include <QListWidget>
#include <QListWidgetItem>

/* 2026-11-10 VS 式主框架扩展（Widgets 核心，非可选模块） */
#include <QMenuBar>
#include <QMenu>
#include <QAction>
#include <QToolBar>
#include <QDockWidget>
#include <QMdiArea>
#include <QMdiSubWindow>
#include <QDialog>

/* 2026-11-03 扩展面（可选模块，vcxproj 一律 /DELAYLOAD；绑定层预装载后命中） */
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QNetworkInformation>
#include <QSqlDatabase>
#include <QSqlQuery>
#include <QSqlError>
#include <QSvgWidget>
#include <QSvgRenderer>
#include <QPrinter>
#include <QPageSize>
#include <QDomDocument>
#include <QtConcurrent>
#include <QThreadPool>
#include <QtTest>
#include <QUiLoader>
#include <QHelpEngine>
#include <QDBusConnection>
#include <QFormBuilder>
#include <QOpenGLWidget>
#include <QOpenGLShaderProgram>
#include <QOpenGLBuffer>
#include <QOpenGLVertexArrayObject>

static QApplication* g_app = nullptr;
static char g_text_buf[8192];

/* 大缓冲（网络 body / XML 串 / 插件清单等；SLang VM 在返回瞬间拷入自身
 * string——顺序调用安全，不支持重入）。 */
static char g_big_buf[262144];

/* QByteArray → 静态缓冲（截断 + NUL），返回缓冲指针。 */
static const char* slqt_put(char* dst, size_t cap, const QByteArray& src)
{
    size_t n = (size_t)src.size();
    if (cap == 0) return dst;
    if (n >= cap) n = cap - 1;
    memcpy(dst, src.constData(), n);
    dst[n] = '\0';
    return dst;
}

static QWidget* asWidget(int64_t h) { return static_cast<QWidget*>((QObject*)slqt_resolve(h)); }

/* ── 非 QObject 对象的类型化析构器侧表 ──────────────────────────────────
 * QSqlDatabase / QSqlQuery / QDomDocument / QPrinter / SlqtConcurrentTask
 * 均非 QObject：通用 object_delete 的 `delete (QObject*)o` 会按 QObject
 * vtable 派发虚析构 → 走错表 → AccessViolation（2026-11-03 实录：QTTest
 * sql 面板 q.delete() 崩溃）。注册表句柄单调递增（slqt_register 插入
 * 下标），侧表按句柄下标平铺；object_delete 先查侧表分派真实析构器。
 * QObject 系（widget/layout/timer/net/svg/uitools/help 等）不注册，
 * 维持原有 delete (QObject*) 虚析构派发。 */
typedef void (*SlqtDtor)(void*);

template <typename T>
static void slqt_dtor_of(void* p) { delete static_cast<T*>(p); }

static SlqtDtor* g_dtor = nullptr;
static int       g_dtor_cap = 0;

static int64_t slqt_register_dtor(void* obj, SlqtDtor dtor)
{
    int64_t h = slqt_register(obj);
    if (h < 0) return h;
    if (h >= (int64_t)g_dtor_cap)
    {
        int ncap = g_dtor_cap ? g_dtor_cap * 2 : 256;
        while (h >= (int64_t)ncap) ncap *= 2;
        SlqtDtor* nd = (SlqtDtor*)calloc((size_t)ncap, sizeof(SlqtDtor));
        if (!nd) return h;
        if (g_dtor)
        {
            memcpy(nd, g_dtor, (size_t)g_dtor_cap * sizeof(SlqtDtor));
            free(g_dtor);
        }
        g_dtor = nd;
        g_dtor_cap = ncap;
    }
    g_dtor[(int)h] = dtor;
    return h;
}

/* ── 应用 ─────────────────────────────────────────────────────────────── */

/* Qt 6 Windows 可重定位前缀基于应用程序目录（QLibraryInfo，Qt7 才计划改为
 * QtCore 装载位），与 Qt6Core.dll 实际装载目录无关——模块包同位部署
 * （slang_qt.dll 与 Qt6*.dll、plugins\platforms\ 同目录，经 FFI 的
 * LOAD_WITH_ALTERED_SEARCH_PATH 自洽装载）后，QApplication 构造期插件
 * 扫描只查 <exe>\platforms 与 QT_QPA_PLATFORM_PLUGIN_PATH，同位
 * plugins\platforms 自动发现落空 → qFatal fail-fast（0xC0000409，
 * QTTest 实录）。且进程内 SetEnvironmentVariable 补设存在读取时机
 * 不可靠问题（实测 set 成功、Qt 构造仍读到空），改经 QApplication
 * 构造参数 -platformpluginpath 注入（构造期解析，时机确定）。 */
/* 本 dll 自身目录（= Qt 运行库同位部署槽位）。 */
static int slqt_be_dll_dir(char* out, size_t out_size)
{
#ifdef _WIN32
    HMODULE self = NULL;
    char dll_path[MAX_PATH];
    DWORD n;
    char* slash;
    if (!GetModuleHandleExA(
            GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS
                | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
            (LPCSTR)&slqt_be_dll_dir, &self)
        || self == NULL)
    {
        return 0;
    }
    n = GetModuleFileNameA(self, dll_path, MAX_PATH);
    if (n == 0 || n >= MAX_PATH)
    {
        return 0;
    }
    slash = strrchr(dll_path, '\\');
    if (slash == NULL)
    {
        return 0;
    }
    *slash = '\0';
    if (strlen(dll_path) + 1 > out_size)
    {
        return 0;
    }
    strcpy(out, dll_path);
    return 1;
#else
    (void)out;
    (void)out_size;
    return 0;
#endif
}

/* 同位 plugins\platforms 存在性探测（argv 注入用）。 */
static int slqt_be_platform_dir(char* out, size_t out_size)
{
    char dll_dir[MAX_PATH];
    if (!slqt_be_dll_dir(dll_dir, sizeof(dll_dir)))
    {
        return 0;
    }
    if (snprintf(out, out_size, "%s\\plugins\\platforms", dll_dir)
        >= (int)out_size
        || GetFileAttributesA(out) == INVALID_FILE_ATTRIBUTES)
    {
        return 0;
    }
    return 1;
}

int64_t slqt_be_app_create(void)
{
    if (!g_app)
    {
        static int    argc = 1;
        static char   arg0[] = "slang_qt";
        static char   arg1[] = "-platformpluginpath";
        static char   plugin_dir[MAX_PATH + 64];
        static char*  argv[4] = { arg0, nullptr };
        /* 用户显式设置了 QT_QPA_PLATFORM_PLUGIN_PATH 时不注入（arg 会
         * 覆盖 env，尊重用户）；否则按 dll 同位 plugins\platforms 注入。 */
        if (GetEnvironmentVariableA("QT_QPA_PLATFORM_PLUGIN_PATH", NULL, 0) == 0
            && slqt_be_platform_dir(plugin_dir, sizeof(plugin_dir)))
        {
            argv[1] = arg1;
            argv[2] = plugin_dir;
            argv[3] = nullptr;
            argc = 3;
            SetEnvironmentVariableA("QT_QPA_PLATFORM_PLUGIN_PATH", plugin_dir);
        }
        g_app = new QApplication(argc, argv);
        /* 同位插件根目录登记进库搜索路径（2026-11-03）：platforms 之外的
         * 插件分类（imageformats / sqldrivers / tls / iconengines /
         * networkinformation / generic…）均惰性装载，构造后立即登记即可
         * 命中同位部署——开发态通道（发布态另有 qt.conf 前缀重定向，
         * 双保险：qt.conf 抑制编译期烘焙的 SDK 前缀，彻底不依赖系统装位）。 */
        char dll_dir[MAX_PATH];
        if (slqt_be_dll_dir(dll_dir, sizeof(dll_dir)))
        {
            char libroot[MAX_PATH + 64];
            if (snprintf(libroot, sizeof(libroot), "%s\\plugins", dll_dir)
                    < (int)sizeof(libroot)
                && GetFileAttributesA(libroot) != INVALID_FILE_ATTRIBUTES)
            {
                QCoreApplication::addLibraryPath(QString::fromUtf8(libroot));
            }
        }
    }
    return slqt_register(g_app);
}

void slqt_be_app_set_stylesheet(const char* c) { if (g_app && c) g_app->setStyleSheet(QString::fromUtf8(c)); }
int32_t slqt_be_app_set_style(const char* n)
{
    if (!g_app || !n) return 0;
    return g_app->setStyle(QString::fromUtf8(n)) != nullptr ? 1 : 0;
}
void slqt_be_app_exec(void) { if (g_app) g_app->exec(); }
void slqt_be_app_process_events(void) { if (g_app) g_app->processEvents(); }
void slqt_be_app_quit(void) { if (g_app) g_app->quit(); }
int32_t slqt_be_app_argc(void) { return g_app ? (int32_t)g_app->arguments().size() : 0; }

/* ── 对象 / 控件 ─────────────────────────────────────────────────────── */
/* 通用删除：非 QObject 句柄按侧表析构器分派（见 asWidget 后侧表注释）；
 * QObject 系走虚析构。删除后注销句柄（resolve 即刻返回 NULL，防悬垂
 * 指针与二次 delete）。 */
void slqt_be_object_delete(int64_t h)
{
    void* o = slqt_resolve(h);
    if (!o) return;
    if (h >= 0 && h < (int64_t)g_dtor_cap && g_dtor[h])
    {
        SlqtDtor d = g_dtor[h];
        g_dtor[h] = nullptr;
        d(o);
    }
    else
    {
        delete (QObject*)o;
    }
    slqt_unregister(h);
}
int32_t slqt_be_object_is_valid(int64_t h) { return slqt_resolve(h) != nullptr ? 1 : 0; }

int64_t slqt_be_widget_create(int64_t p) { QWidget* parent = p ? asWidget(p) : nullptr; return slqt_register(new QWidget(parent)); }

void slqt_be_widget_set_parent(int64_t h, int64_t p)
{
    QWidget* w = asWidget(h);
    QWidget* parent = p ? asWidget(p) : nullptr;
    if (w) w->setParent(parent);
}

void slqt_be_widget_set_text(int64_t h, const char* t)
{
    QObject* o = (QObject*)slqt_resolve(h);
    if (!o || !t) return;
    if (auto* w = qobject_cast<QPushButton*>(o)) { w->setText(QString::fromUtf8(t)); return; }
    if (auto* w = qobject_cast<QLabel*>(o)) { w->setText(QString::fromUtf8(t)); return; }
    if (auto* w = qobject_cast<QLineEdit*>(o)) { w->setText(QString::fromUtf8(t)); return; }
    /* QTextEdit 在 QWidget 兜底之前命中，否则 setWindowTitle 会吃掉正文 */
    if (auto* w = qobject_cast<QTextEdit*>(o)) { w->setPlainText(QString::fromUtf8(t)); return; }
    if (auto* w = qobject_cast<QWidget*>(o)) { w->setWindowTitle(QString::fromUtf8(t)); }
}

const char* slqt_be_widget_text(int64_t h)
{
    QObject* o = (QObject*)slqt_resolve(h);
    if (!o) return "";
    if (auto* w = qobject_cast<QPushButton*>(o)) { QByteArray b = w->text().toUtf8(); snprintf(g_text_buf, sizeof(g_text_buf), "%s", b.constData()); return g_text_buf; }
    if (auto* w = qobject_cast<QLabel*>(o)) { QByteArray b = w->text().toUtf8(); snprintf(g_text_buf, sizeof(g_text_buf), "%s", b.constData()); return g_text_buf; }
    if (auto* w = qobject_cast<QLineEdit*>(o)) { QByteArray b = w->text().toUtf8(); snprintf(g_text_buf, sizeof(g_text_buf), "%s", b.constData()); return g_text_buf; }
    if (auto* w = qobject_cast<QTextEdit*>(o)) { return slqt_put(g_big_buf, sizeof(g_big_buf), w->toPlainText().toUtf8()); }
    return "";
}

void slqt_be_widget_set_geometry(int64_t h, int32_t x, int32_t y, int32_t w, int32_t hh) { QWidget* o = asWidget(h); if (o) o->setGeometry(x, y, w, hh); }
void slqt_be_widget_resize(int64_t h, int32_t w, int32_t hh) { QWidget* o = asWidget(h); if (o) o->resize(w, hh); }
void slqt_be_widget_show(int64_t h) { QWidget* o = asWidget(h); if (o) o->show(); }
void slqt_be_widget_hide(int64_t h) { QWidget* o = asWidget(h); if (o) o->hide(); }
void slqt_be_widget_set_enabled(int64_t h, int32_t on) { QWidget* o = asWidget(h); if (o) o->setEnabled(on != 0); }
void slqt_be_widget_set_visible(int64_t h, int32_t on) { QWidget* o = asWidget(h); if (o) o->setVisible(on != 0); }
void slqt_be_widget_set_tooltip(int64_t h, const char* t) { QWidget* o = asWidget(h); if (o && t) o->setToolTip(QString::fromUtf8(t)); }
void slqt_be_widget_set_style_sheet(int64_t h, const char* c) { QWidget* o = asWidget(h); if (o && c) o->setStyleSheet(QString::fromUtf8(c)); }
void slqt_be_widget_set_fixed_size(int64_t h, int32_t w, int32_t hh) { QWidget* o = asWidget(h); if (o) o->setFixedSize(w, hh); }
void slqt_be_widget_update(int64_t h) { QWidget* o = asWidget(h); if (o) o->update(); }

/* ── 按钮 / 标签 / 输入 ──────────────────────────────────────────────── */
int64_t slqt_be_button_create(int64_t p) { QWidget* parent = p ? asWidget(p) : nullptr; return slqt_register(new QPushButton(parent)); }
int64_t slqt_be_label_create(int64_t p) { QWidget* parent = p ? asWidget(p) : nullptr; return slqt_register(new QLabel(parent)); }
int32_t slqt_be_label_set_pixmap(int64_t h, int64_t ptr, int32_t len) { (void)h; (void)ptr; (void)len; return 0; }
int64_t slqt_be_edit_create(int64_t p) { QWidget* parent = p ? asWidget(p) : nullptr; return slqt_register(new QLineEdit(parent)); }
void slqt_be_edit_set_placeholder(int64_t h, const char* t) { auto* o = qobject_cast<QLineEdit*>((QObject*)slqt_resolve(h)); if (o && t) o->setPlaceholderText(QString::fromUtf8(t)); }
const char* slqt_be_edit_text(int64_t h) { auto* o = qobject_cast<QLineEdit*>((QObject*)slqt_resolve(h)); if (!o) return ""; QByteArray b = o->text().toUtf8(); snprintf(g_text_buf, sizeof(g_text_buf), "%s", b.constData()); return g_text_buf; }
void slqt_be_edit_set_readonly(int64_t h, int32_t on) { auto* o = qobject_cast<QLineEdit*>((QObject*)slqt_resolve(h)); if (o) o->setReadOnly(on != 0); }

/* ── 多行文本编辑 / 列表（QTextEdit / QListWidget）────────────────────── */
int64_t slqt_be_textedit_create(int64_t p) { QWidget* parent = p ? asWidget(p) : nullptr; return slqt_register(new QTextEdit(parent)); }
void slqt_be_textedit_set_text(int64_t h, const char* t) { auto* o = qobject_cast<QTextEdit*>((QObject*)slqt_resolve(h)); if (o) o->setPlainText(QString::fromUtf8(t ? t : "")); }
const char* slqt_be_textedit_text(int64_t h)
{
    auto* o = qobject_cast<QTextEdit*>((QObject*)slqt_resolve(h));
    if (!o) return "";
    return slqt_put(g_big_buf, sizeof(g_big_buf), o->toPlainText().toUtf8());
}
void slqt_be_textedit_set_readonly(int64_t h, int32_t on) { auto* o = qobject_cast<QTextEdit*>((QObject*)slqt_resolve(h)); if (o) o->setReadOnly(on != 0); }
void slqt_be_textedit_append(int64_t h, const char* t) { auto* o = qobject_cast<QTextEdit*>((QObject*)slqt_resolve(h)); if (o && t) o->append(QString::fromUtf8(t)); }

int64_t slqt_be_list_create(int64_t p) { QWidget* parent = p ? asWidget(p) : nullptr; return slqt_register(new QListWidget(parent)); }
void slqt_be_list_add_item(int64_t h, const char* t)
{
    auto* o = qobject_cast<QListWidget*>((QObject*)slqt_resolve(h));
    if (o) o->addItem(QString::fromUtf8(t ? t : ""));
}
void slqt_be_list_clear(int64_t h) { auto* o = qobject_cast<QListWidget*>((QObject*)slqt_resolve(h)); if (o) o->clear(); }
int32_t slqt_be_list_count(int64_t h) { auto* o = qobject_cast<QListWidget*>((QObject*)slqt_resolve(h)); return o ? o->count() : 0; }
int32_t slqt_be_list_current_row(int64_t h) { auto* o = qobject_cast<QListWidget*>((QObject*)slqt_resolve(h)); return o ? o->currentRow() : -1; }
void slqt_be_list_set_current_row(int64_t h, int32_t row) { auto* o = qobject_cast<QListWidget*>((QObject*)slqt_resolve(h)); if (o) o->setCurrentRow(row); }
const char* slqt_be_list_item_text(int64_t h, int32_t row)
{
    auto* o = qobject_cast<QListWidget*>((QObject*)slqt_resolve(h));
    if (!o) return "";
    QListWidgetItem* it = o->item(row);
    if (!it) return "";
    return slqt_put(g_text_buf, sizeof(g_text_buf), it->text().toUtf8());
}

/* ── 主窗口 / 对话框 ─────────────────────────────────────────────────── */
int64_t slqt_be_mainwindow_create(void) { return slqt_register(new QMainWindow()); }
void slqt_be_mainwindow_set_central(int64_t h, int64_t w) { auto* mw = qobject_cast<QMainWindow*>((QObject*)slqt_resolve(h)); if (mw) mw->setCentralWidget(asWidget(w)); }
void slqt_be_mainwindow_set_title(int64_t h, const char* t) { auto* mw = qobject_cast<QMainWindow*>((QObject*)slqt_resolve(h)); if (mw && t) mw->setWindowTitle(QString::fromUtf8(t)); }
void slqt_be_mainwindow_resize(int64_t h, int32_t w, int32_t hh) { auto* mw = qobject_cast<QMainWindow*>((QObject*)slqt_resolve(h)); if (mw) mw->resize(w, hh); }
void slqt_be_mainwindow_show(int64_t h) { auto* mw = qobject_cast<QMainWindow*>((QObject*)slqt_resolve(h)); if (mw) mw->show(); }
int32_t slqt_be_messagebox_info(int64_t p, const char* t, const char* x) { QWidget* parent = p ? asWidget(p) : nullptr; return (int32_t)QMessageBox::information(parent, QString::fromUtf8(t), QString::fromUtf8(x)); }
int32_t slqt_be_messagebox_question(int64_t p, const char* t, const char* x) { QWidget* parent = p ? asWidget(p) : nullptr; return (int32_t)QMessageBox::question(parent, QString::fromUtf8(t), QString::fromUtf8(x)); }

/* ── 布局 ────────────────────────────────────────────────────────────── */
int64_t slqt_be_vbox_create(int64_t p) { QWidget* parent = p ? asWidget(p) : nullptr; return slqt_register(new QVBoxLayout(parent)); }
int64_t slqt_be_hbox_create(int64_t p) { QWidget* parent = p ? asWidget(p) : nullptr; return slqt_register(new QHBoxLayout(parent)); }
int64_t slqt_be_grid_create(int64_t p) { QWidget* parent = p ? asWidget(p) : nullptr; return slqt_register(new QGridLayout(parent)); }

void slqt_be_layout_add_widget(int64_t l, int64_t w) { auto* lo = qobject_cast<QLayout*>((QObject*)slqt_resolve(l)); if (lo) lo->addWidget(asWidget(w)); }
void slqt_be_layout_add_spacing(int64_t l, int32_t px) { auto* bl = qobject_cast<QBoxLayout*>((QObject*)slqt_resolve(l)); if (bl) bl->addSpacing(px); }
void slqt_be_layout_add_stretch(int64_t l, int32_t s) { auto* bl = qobject_cast<QBoxLayout*>((QObject*)slqt_resolve(l)); if (bl) bl->addStretch(s); }
void slqt_be_layout_set_contents_margins(int64_t l, int32_t a, int32_t b, int32_t c, int32_t d) { auto* lo = qobject_cast<QLayout*>((QObject*)slqt_resolve(l)); if (lo) lo->setContentsMargins(a, b, c, d); }
void slqt_be_layout_set_spacing(int64_t l, int32_t px) { auto* lo = qobject_cast<QLayout*>((QObject*)slqt_resolve(l)); if (lo) lo->setSpacing(px); }
void slqt_be_layout_set_widget_at(int64_t g, int64_t w, int32_t r, int32_t c, int32_t rs, int32_t cs)
{
    auto* gl = qobject_cast<QGridLayout*>((QObject*)slqt_resolve(g));
    if (gl) gl->addWidget(asWidget(w), r, c, rs, cs);
}
void slqt_be_widget_set_layout(int64_t w, int64_t l) { QWidget* ww = asWidget(w); auto* lo = qobject_cast<QLayout*>((QObject*)slqt_resolve(l)); if (ww && lo) ww->setLayout(lo); }

/* ── 信号连接：lambda 捕获 (dispatchCb, slot)，发射时重入 SLang VM ─────── */
int64_t slqt_be_connect(int64_t h, int32_t signalId, int64_t dispatchCb, int64_t slot)
{
    QObject* sender = (QObject*)slqt_resolve(h);
    if (!sender) return 0;
    switch (signalId)
    {
    case SLQT_SIG_CLICKED:
        if (auto* b = qobject_cast<QPushButton*>(sender))
            QObject::connect(b, &QPushButton::clicked, [=]() { ((void (*)(int64_t))dispatchCb)(slot); });
        break;
    case SLQT_SIG_RETURN_PRESSED:
        if (auto* e = qobject_cast<QLineEdit*>(sender))
            QObject::connect(e, &QLineEdit::returnPressed, [=]() { ((void (*)(int64_t))dispatchCb)(slot); });
        break;
    case SLQT_SIG_TRIGGERED:
        /* QAction::triggered（菜单/工具栏动作；QAction 是 QObject） */
        if (auto* a = qobject_cast<QAction*>(sender))
            QObject::connect(a, &QAction::triggered, [=]() { ((void (*)(int64_t))dispatchCb)(slot); });
        break;
    case SLQT_SIG_DESTROYED:
        QObject::connect(sender, &QObject::destroyed, [=]() { ((void (*)(int64_t))dispatchCb)(slot); });
        break;
    case SLQT_SIG_TEXT_CHANGED:
        if (auto* e = qobject_cast<QLineEdit*>(sender))
            QObject::connect(e, &QLineEdit::textChanged, [=](const QString& s) {
                QByteArray b = s.toUtf8();
                ((void (*)(int64_t, const char*))dispatchCb)(slot, b.constData());
            });
        break;
    case SLQT_SIG_CURRENT_ROW_CHANGED:
        if (auto* l = qobject_cast<QListWidget*>(sender))
            QObject::connect(l, &QListWidget::currentRowChanged, [=](int row) {
                ((void (*)(int64_t, int64_t))dispatchCb)(slot, (int64_t)row);
            });
        break;
    default:
        break;
    }
    return 1;
}

/* ========================================================================
 * 2026-11-03 扩展面实现（Qt6 真实后端）。可选模块经 /DELAYLOAD 链接，
 * 绑定层预装载 + 调用方探测兜底（slqt_module_available_sl）。
 * ======================================================================== */

const char* slqt_be_backend_kind(void) { return "qt"; }

const char* slqt_be_app_platform_name(void)
{
    snprintf(g_text_buf, sizeof(g_text_buf), "%s",
             QGuiApplication::platformName().toUtf8().constData());
    return g_text_buf;
}

const char* slqt_be_app_library_paths(void)
{
    return slqt_put(g_big_buf, sizeof(g_big_buf),
                    QCoreApplication::libraryPaths().join(';').toUtf8());
}

const char* slqt_be_app_style_keys(void)
{
    return slqt_put(g_big_buf, sizeof(g_big_buf),
                    QStyleFactory::keys().join(';').toUtf8());
}

/* ── 控件移动 + QTimer（动画面板）──────────────────────────────────────── */

void slqt_be_widget_move(int64_t h, int32_t x, int32_t y)
{
    QWidget* o = asWidget(h);
    if (o) o->move(x, y);
}

int64_t slqt_be_timer_create(int32_t ms, int32_t single, int64_t dispatchCb, int64_t slot)
{
    if (!dispatchCb) return 0;
    QTimer* t = new QTimer(nullptr);
    t->setSingleShot(single != 0);
    QObject::connect(t, &QTimer::timeout, [=]() { ((void (*)(int64_t))dispatchCb)(slot); });
    if (ms > 0) t->start(ms);
    return slqt_register(t);
}

void slqt_be_timer_delete(int64_t h)
{
    auto* t = qobject_cast<QTimer*>((QObject*)slqt_resolve(h));
    if (t) { t->stop(); delete t; }
}

void slqt_be_timer_start(int64_t h, int32_t ms)
{
    auto* t = qobject_cast<QTimer*>((QObject*)slqt_resolve(h));
    if (t) t->start(ms);
}

void slqt_be_timer_stop(int64_t h)
{
    auto* t = qobject_cast<QTimer*>((QObject*)slqt_resolve(h));
    if (t) t->stop();
}

int32_t slqt_be_timer_active(int64_t h)
{
    auto* t = qobject_cast<QTimer*>((QObject*)slqt_resolve(h));
    return (t && t->isActive()) ? 1 : 0;
}

/* ── Network（Qt6Network；networkinformation / tls 插件）───────────────── */

int64_t slqt_be_net_create(void) { return slqt_register(new QNetworkAccessManager()); }

void slqt_be_net_delete(int64_t h)
{
    auto* m = static_cast<QNetworkAccessManager*>((QObject*)slqt_resolve(h));
    if (m) delete m;
}

int32_t slqt_be_net_is_online(void)
{
    /* Qt 6.8：isOnline() 移除，改 reachability 判定（qnetworkinformation.h）。 */
    if (!QNetworkInformation::loadDefaultBackend()) return -1;
    auto* n = QNetworkInformation::instance();
    return (n && n->reachability() == QNetworkInformation::Reachability::Online) ? 1 : 0;
}

const char* slqt_be_net_backend_name(void)
{
    static char buf[256];
    buf[0] = '\0';
    if (QNetworkInformation::loadDefaultBackend() && QNetworkInformation::instance())
    {
        snprintf(buf, sizeof(buf), "%s",
                 QNetworkInformation::instance()->backendName().toUtf8().constData());
    }
    return buf;
}

int64_t slqt_be_net_get(int64_t h, const char* url)
{
    auto* m = static_cast<QNetworkAccessManager*>((QObject*)slqt_resolve(h));
    if (!m || !url) return 0;
    QNetworkReply* r = m->get(QNetworkRequest(QUrl(QString::fromUtf8(url))));
    return r ? slqt_register(r) : 0;
}

void slqt_be_net_reply_delete(int64_t h)
{
    auto* r = static_cast<QNetworkReply*>((QObject*)slqt_resolve(h));
    if (r) { r->deleteLater(); }
}

int32_t slqt_be_net_reply_wait(int64_t h, int32_t ms)
{
    auto* r = static_cast<QNetworkReply*>((QObject*)slqt_resolve(h));
    if (!r) return 0;
    if (r->isFinished()) return 1;
    QEventLoop loop;
    /* 不能用 PMF connect：qobject.h 的 connect 模板会取
     * &QNetworkReply::staticMetaObject（数据符号导入），Qt6Network 是
     * /DELAYLOAD 模块 → LNK1194。字符串形式运行期解析，无数据导入。 */
    QObject::connect(r, SIGNAL(finished()), &loop, SLOT(quit()));
    QTimer::singleShot(ms, &loop, &QEventLoop::quit);
    loop.exec();
    return r->isFinished() ? 1 : 0;
}

int32_t slqt_be_net_reply_status(int64_t h)
{
    auto* r = static_cast<QNetworkReply*>((QObject*)slqt_resolve(h));
    if (!r || !r->isFinished()) return -1;
    return (int32_t)r->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
}

const char* slqt_be_net_reply_error(int64_t h)
{
    auto* r = static_cast<QNetworkReply*>((QObject*)slqt_resolve(h));
    if (!r) return "";
    return slqt_put(g_big_buf, sizeof(g_big_buf),
                    r->errorString().toUtf8());
}

const char* slqt_be_net_reply_body(int64_t h)
{
    auto* r = static_cast<QNetworkReply*>((QObject*)slqt_resolve(h));
    if (!r || !r->isFinished()) return "";
    return slqt_put(g_big_buf, sizeof(g_big_buf), r->readAll());
}

/* ── Sql（Qt6Sql；sqldrivers 插件）────────────────────────────────────── */

const char* slqt_be_sql_drivers(void)
{
    return slqt_put(g_big_buf, sizeof(g_big_buf),
                    QSqlDatabase::drivers().join(';').toUtf8());
}

int64_t slqt_be_sql_add_database(const char* type)
{
    if (!type) return 0;
    /* addDatabase(type) 一参重载内联引用 QSqlDatabase::defaultConnection
     * （数据符号导入，Qt6Sql 是 /DELAYLOAD 模块 → LNK1194），改二参重载；
     * 顺带自增连接名避免重复 add 的重名告警（remove 按 connectionName 对账）。 */
    static int seq = 0;
    char cname[32];
    snprintf(cname, sizeof(cname), "slqt_conn_%d", ++seq);
    QSqlDatabase db = QSqlDatabase::addDatabase(QString::fromUtf8(type),
                                                QString::fromLatin1(cname));
    return slqt_register_dtor(new QSqlDatabase(db), slqt_dtor_of<QSqlDatabase>);
}

void slqt_be_sql_delete(int64_t h)
{
    auto* db = (QSqlDatabase*)slqt_resolve(h);
    if (!db) return;
    QString name = db->connectionName();
    delete db;
    QSqlDatabase::removeDatabase(name);
    slqt_unregister(h);
}

void slqt_be_sql_set_database_name(int64_t h, const char* name)
{
    auto* db = (QSqlDatabase*)slqt_resolve(h);
    if (db && name) db->setDatabaseName(QString::fromUtf8(name));
}

int32_t slqt_be_sql_open(int64_t h)
{
    auto* db = (QSqlDatabase*)slqt_resolve(h);
    if (!db) return 0;
    /* QSQLITE 在此触发 sqldrivers\qsqlite.dll 装载（探测点）。 */
    return db->open() ? 1 : 0;
}

void slqt_be_sql_close(int64_t h)
{
    auto* db = (QSqlDatabase*)slqt_resolve(h);
    if (db && db->isOpen()) db->close();
}

const char* slqt_be_sql_last_error(int64_t h)
{
    auto* db = (QSqlDatabase*)slqt_resolve(h);
    if (!db) return "";
    return slqt_put(g_big_buf, sizeof(g_big_buf),
                    db->lastError().text().toUtf8());
}

int64_t slqt_be_sql_query_create(int64_t db)
{
    auto* d = (QSqlDatabase*)slqt_resolve(db);
    if (!d) return 0;
    return slqt_register_dtor(new QSqlQuery(*d), slqt_dtor_of<QSqlQuery>);
}

void slqt_be_sql_query_delete(int64_t h)
{
    auto* q = (QSqlQuery*)slqt_resolve(h);
    if (q) delete q;
    slqt_unregister(h);
}

int32_t slqt_be_sql_query_exec(int64_t h, const char* sql)
{
    auto* q = (QSqlQuery*)slqt_resolve(h);
    if (!q) return 0;
    if (sql) return q->exec(QString::fromUtf8(sql)) ? 1 : 0;
    return q->exec() ? 1 : 0;
}

int32_t slqt_be_sql_query_next(int64_t h)
{
    auto* q = (QSqlQuery*)slqt_resolve(h);
    return (q && q->next()) ? 1 : 0;
}

const char* slqt_be_sql_query_value_text(int64_t h, int32_t i)
{
    auto* q = (QSqlQuery*)slqt_resolve(h);
    if (!q) return "";
    return slqt_put(g_text_buf, sizeof(g_text_buf),
                    q->value(i).toString().toUtf8());
}

int64_t slqt_be_sql_query_value_int(int64_t h, int32_t i)
{
    auto* q = (QSqlQuery*)slqt_resolve(h);
    if (!q) return 0;
    return q->value(i).toLongLong();
}

/* ── Svg（Qt6Svg / Qt6SvgWidgets）─────────────────────────────────────── */

int64_t slqt_be_svgwidget_create(int64_t p)
{
    QWidget* parent = p ? asWidget(p) : nullptr;
    return slqt_register(new QSvgWidget(parent));
}

int32_t slqt_be_svgwidget_load_file(int64_t h, const char* path)
{
    auto* w = static_cast<QSvgWidget*>((QObject*)slqt_resolve(h));
    if (!w || !path) return 0;
    w->load(QString::fromUtf8(path));   /* load 返回 void（slot），失败靠 renderer 判定 */
    return 1;
}

int32_t slqt_be_svgwidget_load_data(int64_t h, const char* xml)
{
    auto* w = static_cast<QSvgWidget*>((QObject*)slqt_resolve(h));
    if (!w || !xml) return 0;
    w->load(QByteArray(xml));
    return 1;
}

int64_t slqt_be_svg_renderer_create(const char* xml)
{
    if (!xml) return 0;
    auto* r = new QSvgRenderer(QByteArray(xml));
    return slqt_register(r);
}

void slqt_be_svg_renderer_delete(int64_t h)
{
    auto* r = static_cast<QSvgRenderer*>((QObject*)slqt_resolve(h));
    if (r) delete r;
}

int32_t slqt_be_svg_renderer_valid(int64_t h)
{
    auto* r = static_cast<QSvgRenderer*>((QObject*)slqt_resolve(h));
    return (r && r->isValid()) ? 1 : 0;
}

int32_t slqt_be_svg_renderer_check_size(int64_t h, int32_t w, int32_t hh)
{
    auto* r = static_cast<QSvgRenderer*>((QObject*)slqt_resolve(h));
    if (!r || !r->isValid()) return 0;
    QSize s = r->defaultSize();
    return (s.width() == w && s.height() == hh) ? 1 : 0;
}

int32_t slqt_be_svg_render_to_label(int64_t renderer, int64_t label, int32_t w, int32_t hh)
{
    auto* r = static_cast<QSvgRenderer*>((QObject*)slqt_resolve(renderer)); /* Qt6Svg /DELAYLOAD：禁 qobject_cast（数据符号） */
    auto* l = qobject_cast<QLabel*>((QObject*)slqt_resolve(label));
    if (!r || !l || !r->isValid()) return 0;
    QPixmap pm(w, hh);
    pm.fill(Qt::transparent);
    {
        QPainter p(&pm);
        r->render(&p);
    }
    l->setPixmap(pm);
    return 1;
}

/* ── 图像 / 图标（Qt6Gui；imageformats / iconengines 插件探测）─────────── */

const char* slqt_be_image_formats(void)
{
    /* supportedImageFormats 扫描 imageformats 插件（gif/ico/jpeg/svg…）。 */
    QStringList list;
    const auto fmts = QImageReader::supportedImageFormats();
    for (const auto& f : fmts) list << QString::fromLatin1(f);
    return slqt_put(g_big_buf, sizeof(g_big_buf), list.join(';').toUtf8());
}

int32_t slqt_be_image_save_solid(const char* path, const char* fmt, int32_t r, int32_t g, int32_t b)
{
    if (!path) return 0;
    QImage img(32, 32, QImage::Format_RGB32);
    img.fill(qRgb(r, g, b));
    /* QImage::save 按格式走对应插件的写通道（gif/jpeg…探测点）。 */
    return img.save(QString::fromUtf8(path), fmt ? fmt : "PNG") ? 1 : 0;
}

int32_t slqt_be_image_check_size(const char* path, int32_t w, int32_t hh)
{
    if (!path) return 0;
    QImage img(QString::fromUtf8(path));
    if (img.isNull()) return 0;
    return (img.width() == w && img.height() == hh) ? 1 : 0;
}

int32_t slqt_be_icon_render(const char* path, int32_t size)
{
    if (!path) return 0;
    /* QIcon(路径) 走 iconengines 插件（.svg → qsvgicon）渲染。 */
    QIcon icon(QString::fromUtf8(path));
    QPixmap pm = icon.pixmap(size, size);
    return pm.isNull() ? 0 : 1;
}

/* ── OpenGL（旋转三角动画面板；无 Q_OBJECT，无需 moc）─────────────────── */

class SlqtGLWidget : public QOpenGLWidget
{
public:
    explicit SlqtGLWidget(QWidget* parent = nullptr)
        : QOpenGLWidget(parent), m_frames(0), m_r(70), m_g(130), m_b(180),
          m_spin(false), m_angle(0.0f) {}

    void slqtSetColor(int r, int g, int b) { m_r = r; m_g = g; m_b = b; update(); }
    void slqtSetSpinning(bool on) { m_spin = on; update(); }
    int64_t slqtFrames() const { return m_frames; }

protected:
    /* 崩溃复盘（2026-11-03 真实窗口 GL 面板）：setAttributeBuffer 在
     * VBO 未绑定状态下调用时，Qt 把 offset 当"客户端指针"（=地址 0）
     * 记入 VAO；核心 profile 下 glDrawArrays 从 NULL 读顶点 → NVIDIA
     * ICD 生成的 thunk（堆可执行页 +0xff3c）空读崩溃（0xC0000005，
     * 三次复现地址同构）。修复：VAO 绑定作用域内先重绑 VBO，使
     * setAttributeBuffer 走 VBO 相对偏移路径。 */
    void initializeGL() override
    {
        m_prog = new QOpenGLShaderProgram(this);
        static const char* vs =
            "#version 330 core\n"
            "layout(location=0) in vec2 pos;\n"
            "uniform float angle;\n"
            "void main(){ float c=cos(angle), s=sin(angle);"
            " gl_Position = vec4(mat2(c,-s,s,c)*pos, 0.0, 1.0); }\n";
        static const char* fs =
            "#version 330 core\n"
            "uniform vec3 col;\n"
            "void main(){ gl_FragColor = vec4(col, 1.0); }\n";
        m_prog->addShaderFromSourceCode(QOpenGLShader::Vertex, vs);
        m_prog->addShaderFromSourceCode(QOpenGLShader::Fragment, fs);
        m_prog->link();
        static const float verts[6] = { 0.0f, 0.6f, -0.6f, -0.4f, 0.6f, -0.4f };
        m_vbo.create();
        m_vbo.bind();
        m_vbo.allocate(verts, sizeof(verts));
        m_vbo.release();
        m_vao.create();
        m_vao.bind();
        m_vbo.bind(); /* setAttributeBuffer 需要 GL_ARRAY_BUFFER 绑定态 */
        if (m_prog->isLinked())
        {
            m_prog->bind();
            m_prog->enableAttributeArray(0);
            m_prog->setAttributeBuffer(0, GL_FLOAT, 0, 2);
            m_prog->release();
        }
        m_vbo.release();
        m_vao.release();
    }

    void paintGL() override
    {
        m_frames++;
        glClearColor(m_r / 255.0f, m_g / 255.0f, m_b / 255.0f, 1.0f);
        glClear(GL_COLOR_BUFFER_BIT);
        if (m_prog && m_prog->isLinked())
        {
            m_prog->bind();
            m_vao.bind();
            m_prog->setUniformValue("angle", m_angle);
            m_prog->setUniformValue("col", m_r / 255.0f, m_g / 255.0f, m_b / 255.0f);
            glDrawArrays(GL_TRIANGLES, 0, 3);
            m_vao.release();
            m_prog->release();
        }
        if (m_spin) { m_angle += 0.05f; update(); }  /* 旋转动画循环 */
    }

private:
    QOpenGLShaderProgram* m_prog = nullptr;
    QOpenGLBuffer m_vbo;
    QOpenGLVertexArrayObject m_vao;
    int64_t m_frames;
    int m_r, m_g, m_b;
    bool m_spin;
    float m_angle;
};

int64_t slqt_be_glwidget_create(int64_t p)
{
    QWidget* parent = p ? asWidget(p) : nullptr;
    return slqt_register(new SlqtGLWidget(parent));
}

void slqt_be_glwidget_set_color(int64_t h, int32_t r, int32_t g, int32_t b)
{
    auto* w = static_cast<SlqtGLWidget*>((QObject*)slqt_resolve(h));
    if (w) w->slqtSetColor(r, g, b);
}

void slqt_be_glwidget_set_spinning(int64_t h, int32_t on)
{
    auto* w = static_cast<SlqtGLWidget*>((QObject*)slqt_resolve(h));
    if (w) w->slqtSetSpinning(on != 0);
}

int64_t slqt_be_glwidget_frame_count(int64_t h)
{
    auto* w = static_cast<SlqtGLWidget*>((QObject*)slqt_resolve(h));
    return w ? w->slqtFrames() : 0;
}

/* ── Print（Qt6PrintSupport；PDF 输出，无对话框）───────────────────────── */

int64_t slqt_be_printer_create(void)
{
    auto* pr = new QPrinter(QPrinter::HighResolution);
    pr->setOutputFormat(QPrinter::PdfFormat);
    return slqt_register_dtor(pr, slqt_dtor_of<QPrinter>);
}

void slqt_be_printer_delete(int64_t h)
{
    auto* pr = static_cast<QPrinter*>(slqt_resolve(h));
    if (pr) delete pr;
    slqt_unregister(h);
}

void slqt_be_printer_set_output_filename(int64_t h, const char* path)
{
    auto* pr = static_cast<QPrinter*>(slqt_resolve(h));
    if (pr && path) pr->setOutputFileName(QString::fromUtf8(path));
}

void slqt_be_printer_set_page_size_a4(int64_t h)
{
    auto* pr = static_cast<QPrinter*>(slqt_resolve(h));
    if (pr) pr->setPageSize(QPageSize(QPageSize::A4));
}

int32_t slqt_be_printer_print_text(int64_t h, const char* title, const char* body)
{
    auto* pr = static_cast<QPrinter*>(slqt_resolve(h));
    if (!pr) return 0;
    QPainter p(pr);
    if (!p.isActive()) return 0;
    QFont f = p.font();
    f.setPointSize(22);
    p.setFont(f);
    p.drawText(200, 400, QString::fromUtf8(title));
    f.setPointSize(11);
    p.setFont(f);
    QRectF area = pr->pageRect(QPrinter::DevicePixel);
    area.adjust(200, 200, -200, -400);
    p.drawText(area, Qt::TextWordWrap, QString::fromUtf8(body));
    p.end();
    return 1;
}

const char* slqt_be_printer_output_file(int64_t h)
{
    auto* pr = static_cast<QPrinter*>(slqt_resolve(h));
    if (!pr) return "";
    return slqt_put(g_text_buf, sizeof(g_text_buf),
                    pr->outputFileName().toUtf8());
}

/* ── Xml（Qt6Xml；QDomDocument）───────────────────────────────────────── */

int64_t slqt_be_dom_create(void) { return slqt_register_dtor(new QDomDocument(), slqt_dtor_of<QDomDocument>); }

void slqt_be_dom_delete(int64_t h)
{
    auto* d = (QDomDocument*)slqt_resolve(h);
    if (d) delete d;
    slqt_unregister(h);
}

int32_t slqt_be_dom_set_content(int64_t h, const char* xml)
{
    auto* d = (QDomDocument*)slqt_resolve(h);
    if (!d || !xml) return 0;
    return d->setContent(QByteArray(xml)) ? 1 : 0;
}

const char* slqt_be_dom_root_tag(int64_t h)
{
    auto* d = (QDomDocument*)slqt_resolve(h);
    if (!d) return "";
    return slqt_put(g_text_buf, sizeof(g_text_buf),
                    d->documentElement().tagName().toUtf8());
}

int64_t slqt_be_dom_count_by_tag(int64_t h, const char* tag)
{
    auto* d = (QDomDocument*)slqt_resolve(h);
    if (!d || !tag) return 0;
    return (int64_t)d->elementsByTagName(QString::fromUtf8(tag)).length();
}

const char* slqt_be_dom_first_text(int64_t h, const char* tag)
{
    auto* d = (QDomDocument*)slqt_resolve(h);
    if (!d || !tag) return "";
    QDomNodeList l = d->elementsByTagName(QString::fromUtf8(tag));
    if (l.isEmpty()) return "";
    return slqt_put(g_text_buf, sizeof(g_text_buf),
                    l.item(0).toElement().text().toUtf8());
}

const char* slqt_be_dom_to_string(int64_t h)
{
    auto* d = (QDomDocument*)slqt_resolve(h);
    if (!d) return "";
    return slqt_put(g_big_buf, sizeof(g_big_buf), d->toString().toUtf8());
}

/* ── Concurrent（Qt6Concurrent；工作线程原生计算）────────────────────── */

struct SlqtConcurrentTask { QFuture<int64_t> fut; };

/* QtConcurrent::ThreadEngineBase 最小派生：其构造/析构/isCanceled 是
 * Q_CONCURRENT_EXPORT 成员（Qt6Concurrent 仅有的非模板导出面）。
 * QtConcurrent::run 是内联模板、底层落到 QtCore 的 QThreadPool，不引用
 * 本模块任何符号——引用 ThreadEngineBase 才能让链接器为 Qt6Concurrent.dll
 * 生成 /DELAYLOAD 桩（组合部署缺件时 SLang 侧已按模块探测 SKIP，桩不触发）。*/
class SlqtConcurrentProbe final : public QtConcurrent::ThreadEngineBase
{
public:
    explicit SlqtConcurrentProbe(QThreadPool* pool) : ThreadEngineBase(pool) {}
    void asynchronousFinish() override {}
};

int64_t slqt_be_concurrent_task_create(int32_t kind, int64_t n)
{
    if (kind != 0 && kind != 1) return 0;
    /* 首次创建任务时做一次只读探测（构造 + isCanceled + 析构），使
     * Qt6Concurrent.dll 延迟桩在运行期被真实命中（dll 装载并参与计算）。 */
    static bool probe = [] {
        SlqtConcurrentProbe p(QThreadPool::globalInstance());
        return p.isCanceled(); /* futureInterface 为 null → false，无副作用 */
    }();
    (void)probe;
    auto* t = new SlqtConcurrentTask();
    if (kind == 0)
    {
        t->fut = QtConcurrent::run([n]() {
            int64_t s = 0;
            for (int64_t i = 1; i <= n; i++) s += i;
            return s;
        });
    }
    else
    {
        t->fut = QtConcurrent::run([n]() {
            int64_t c = 0;
            for (int64_t i = 2; i < n; i++)
            {
                bool p = true;
                for (int64_t j = 2; j * j <= i; j++)
                    if (i % j == 0) { p = false; break; }
                if (p) c++;
            }
            return c;
        });
    }
    return slqt_register_dtor(t, slqt_dtor_of<SlqtConcurrentTask>);
}

void slqt_be_concurrent_task_delete(int64_t h)
{
    auto* t = (SlqtConcurrentTask*)slqt_resolve(h);
    if (t) delete t;
    slqt_unregister(h);
}

int32_t slqt_be_concurrent_task_is_finished(int64_t h)
{
    auto* t = (SlqtConcurrentTask*)slqt_resolve(h);
    return (t && t->fut.isFinished()) ? 1 : 0;
}

int64_t slqt_be_concurrent_task_result(int64_t h)
{
    auto* t = (SlqtConcurrentTask*)slqt_resolve(h);
    if (!t || !t->fut.isFinished()) return 0;
    return t->fut.result();
}

int32_t slqt_be_thread_pool_max(void)
{
    return QThreadPool::globalInstance()
        ? QThreadPool::globalInstance()->maxThreadCount() : 0;
}

/* ── Test（Qt6Test）───────────────────────────────────────────────────── */

/* Qt 6.8：qSleep/qWait 已移入 QtCore（Q_CORE_EXPORT，qtestsupport_core.h），
 * Qt6Test.dll 本身不承载它们。引用一次 Qt6Test 导出符号（qVerify 为纯函数、
 * 无数据符号，statement=true 仅记一条 PASS 日志），使链接器为 Qt6Test.dll
 * 生成 /DELAYLOAD 桩。 */
void slqt_be_test_qsleep(int32_t ms)
{
    QTest::qSleep(ms);
    static bool probe = QTest::qVerify(true, "QtTest probe", "", __FILE__, __LINE__);
    (void)probe;
}
void slqt_be_test_qwait(int32_t ms) { QTest::qWait(ms); }
const char* slqt_be_test_version(void) { return QTEST_VERSION_STR; }

/* ── UiTools / Designer（.ui 文件装载双通道）──────────────────────────── */

int64_t slqt_be_uiloader_create(void) { return slqt_register(new QUiLoader()); }

void slqt_be_uiloader_delete(int64_t h)
{
    auto* l = static_cast<QUiLoader*>((QObject*)slqt_resolve(h));
    if (l) delete l;
}

int64_t slqt_be_uiloader_load_file(int64_t h, const char* path, int64_t p)
{
    auto* l = static_cast<QUiLoader*>((QObject*)slqt_resolve(h));
    if (!l || !path) return 0;
    QFile f(QString::fromUtf8(path));
    if (!f.open(QIODevice::ReadOnly)) return 0;
    QWidget* w = l->load(&f, p ? asWidget(p) : nullptr);
    return w ? slqt_register(w) : 0;
}

const char* slqt_be_uiloader_available_widgets(int64_t h)
{
    auto* l = static_cast<QUiLoader*>((QObject*)slqt_resolve(h));
    if (!l) return "";
    return slqt_put(g_big_buf, sizeof(g_big_buf),
                    l->availableWidgets().join(';').toUtf8());
}

int64_t slqt_be_designer_formbuilder_create(void) { return slqt_register(new QFormBuilder()); }

void slqt_be_designer_formbuilder_delete(int64_t h)
{
    auto* b = (QFormBuilder*)slqt_resolve(h);
    if (b) delete b;
}

int64_t slqt_be_designer_formbuilder_load(int64_t h, const char* path, int64_t p)
{
    auto* b = (QFormBuilder*)slqt_resolve(h);
    if (!b || !path) return 0;
    QFile f(QString::fromUtf8(path));
    if (!f.open(QIODevice::ReadOnly)) return 0;
    QWidget* w = b->load(&f, p ? asWidget(p) : nullptr);
    return w ? slqt_register(w) : 0;
}

/* ── Help（Qt6Help）───────────────────────────────────────────────────── */

int64_t slqt_be_help_engine_create(const char* collection)
{
    if (!collection) return 0;
    /* QHelpEngine 底层走 Qt6Sql + qsqlite 插件（依赖链探测点）。 */
    return slqt_register(new QHelpEngine(QString::fromUtf8(collection)));
}

void slqt_be_help_engine_delete(int64_t h)
{
    auto* e = static_cast<QHelpEngine*>((QObject*)slqt_resolve(h));
    if (e) delete e;
}

int32_t slqt_be_help_setup_data(int64_t h)
{
    auto* e = static_cast<QHelpEngine*>((QObject*)slqt_resolve(h));
    return (e && e->setupData()) ? 1 : 0;
}

const char* slqt_be_help_error(int64_t h)
{
    auto* e = static_cast<QHelpEngine*>((QObject*)slqt_resolve(h));
    if (!e) return "";
    return slqt_put(g_text_buf, sizeof(g_text_buf),
                    e->error().toUtf8());
}

/* ── DBus（Qt6DBus）───────────────────────────────────────────────────── */

int32_t slqt_be_dbus_connected(void)
{
    return QDBusConnection::sessionBus().isConnected() ? 1 : 0;
}

const char* slqt_be_dbus_base_service(void)
{
    static char buf[128];
    snprintf(buf, sizeof(buf), "%s",
             QDBusConnection::sessionBus().baseService().toUtf8().constData());
    return buf;
}

/* ========================================================================
 * 2026-11-10 VS 式主框架扩展实现（菜单/工具栏/Dock/MDI/对话框）
 * ======================================================================== */

/* ── 菜单（QMenuBar / QMenu / QAction）────────────────────────────────── */

int64_t slqt_be_menubar_create(void) { return slqt_register(new QMenuBar()); }

void slqt_be_mainwindow_set_menubar(int64_t win, int64_t mb)
{
    auto* mw = qobject_cast<QMainWindow*>((QObject*)slqt_resolve(win));
    auto* bar = qobject_cast<QMenuBar*>((QObject*)slqt_resolve(mb));
    if (mw && bar) mw->setMenuBar(bar);
}

/* parent 为 QMenuBar（一级菜单）或 QMenu（二级/子菜单） */
int64_t slqt_be_menu_create(int64_t parent, const char* title)
{
    QObject* p = (QObject*)slqt_resolve(parent);
    QString t = QString::fromUtf8(title ? title : "");
    if (auto* mb = qobject_cast<QMenuBar*>(p)) return slqt_register(mb->addMenu(t));
    if (auto* m = qobject_cast<QMenu*>(p)) return slqt_register(m->addMenu(t));
    return 0;
}

/* 菜单项：menu->addAction(text) 返回 QAction，登记句柄供 connect(triggered) */
int64_t slqt_be_menu_add_action(int64_t menu, const char* text)
{
    auto* m = qobject_cast<QMenu*>((QObject*)slqt_resolve(menu));
    if (!m) return 0;
    QAction* a = m->addAction(QString::fromUtf8(text ? text : ""));
    return a ? slqt_register(a) : 0;
}

void slqt_be_menu_add_separator(int64_t menu)
{
    auto* m = qobject_cast<QMenu*>((QObject*)slqt_resolve(menu));
    if (m) m->addSeparator();
}

void slqt_be_action_set_text(int64_t a, const char* t)
{
    auto* act = qobject_cast<QAction*>((QObject*)slqt_resolve(a));
    if (act && t) act->setText(QString::fromUtf8(t));
}

void slqt_be_action_set_enabled(int64_t a, int32_t on)
{
    auto* act = qobject_cast<QAction*>((QObject*)slqt_resolve(a));
    if (act) act->setEnabled(on != 0);
}

/* ── 工具栏（QToolBar，快捷图标区）────────────────────────────────────── */

int64_t slqt_be_toolbar_create(int64_t parent, const char* title)
{
    QWidget* parentW = parent ? asWidget(parent) : nullptr;
    QToolBar* tb = new QToolBar(QString::fromUtf8(title ? title : ""), parentW);
    return slqt_register(tb);
}

void slqt_be_mainwindow_add_toolbar(int64_t win, int64_t tb)
{
    auto* mw = qobject_cast<QMainWindow*>((QObject*)slqt_resolve(win));
    auto* bar = qobject_cast<QToolBar*>((QObject*)slqt_resolve(tb));
    if (mw && bar) mw->addToolBar(Qt::TopToolBarArea, bar);
}

int64_t slqt_be_toolbar_add_action(int64_t tb, const char* text)
{
    auto* bar = qobject_cast<QToolBar*>((QObject*)slqt_resolve(tb));
    if (!bar) return 0;
    QAction* a = bar->addAction(QString::fromUtf8(text ? text : ""));
    return a ? slqt_register(a) : 0;
}

void slqt_be_toolbar_add_separator(int64_t tb)
{
    auto* bar = qobject_cast<QToolBar*>((QObject*)slqt_resolve(tb));
    if (bar) bar->addSeparator();
}

/* ── Dock（QDockWidget 自由停靠面板）──────────────────────────────────── */

int64_t slqt_be_dock_create(int64_t parent, const char* title)
{
    QWidget* parentW = parent ? asWidget(parent) : nullptr;
    QDockWidget* d = new QDockWidget(QString::fromUtf8(title ? title : ""), parentW);
    /* VS 式：可关、可浮动、可拖拽；默认不过度嵌套 */
    d->setFeatures(QDockWidget::DockWidgetClosable | QDockWidget::DockWidgetFloatable | QDockWidget::DockWidgetMovable);
    return slqt_register(d);
}

/* area 传 Qt::DockWidgetArea 位值：1=左 2=右 4=顶 8=底 */
void slqt_be_mainwindow_add_dock(int64_t win, int64_t dock, int32_t area)
{
    auto* mw = qobject_cast<QMainWindow*>((QObject*)slqt_resolve(win));
    auto* d = qobject_cast<QDockWidget*>((QObject*)slqt_resolve(dock));
    if (mw && d) mw->addDockWidget((Qt::DockWidgetArea)area, d);
}

void slqt_be_dock_set_widget(int64_t dock, int64_t w)
{
    auto* d = qobject_cast<QDockWidget*>((QObject*)slqt_resolve(dock));
    QWidget* cw = asWidget(w);
    if (d) d->setWidget(cw);
}

void slqt_be_dock_set_features(int64_t dock, int32_t f)
{
    auto* d = qobject_cast<QDockWidget*>((QObject*)slqt_resolve(dock));
    if (d) d->setFeatures((QDockWidget::DockWidgetFeatures)f);
}

void slqt_be_dock_set_floating(int64_t dock, int32_t on)
{
    auto* d = qobject_cast<QDockWidget*>((QObject*)slqt_resolve(dock));
    if (d) d->setFloating(on != 0);
}

/* ── MDI（QMdiArea 多文档代码区）──────────────────────────────────────── */

int64_t slqt_be_mdiarea_create(int64_t parent)
{
    QWidget* parentW = parent ? asWidget(parent) : nullptr;
    return slqt_register(new QMdiArea(parentW));
}

int64_t slqt_be_mdiarea_add_subwindow(int64_t mdi, int64_t w)
{
    auto* area = qobject_cast<QMdiArea*>((QObject*)slqt_resolve(mdi));
    QWidget* cw = asWidget(w);
    if (!area || !cw) return 0;
    QMdiSubWindow* sub = area->addSubWindow(cw);
    return sub ? slqt_register(sub) : 0;
}

int32_t slqt_be_mdiarea_count(int64_t mdi)
{
    auto* area = qobject_cast<QMdiArea*>((QObject*)slqt_resolve(mdi));
    return area ? area->subWindowList().count() : 0;
}

void slqt_be_mdiarea_tile(int64_t mdi)
{
    auto* area = qobject_cast<QMdiArea*>((QObject*)slqt_resolve(mdi));
    if (area) area->tileSubWindows();
}

void slqt_be_mdiarea_cascade(int64_t mdi)
{
    auto* area = qobject_cast<QMdiArea*>((QObject*)slqt_resolve(mdi));
    if (area) area->cascadeSubWindows();
}

void slqt_be_mdiarea_close_active(int64_t mdi)
{
    auto* area = qobject_cast<QMdiArea*>((QObject*)slqt_resolve(mdi));
    if (area) area->closeActiveSubWindow();
}

int64_t slqt_be_mdiarea_active_sub(int64_t mdi)
{
    auto* area = qobject_cast<QMdiArea*>((QObject*)slqt_resolve(mdi));
    if (!area) return 0;
    QMdiSubWindow* sub = area->activeSubWindow();
    return sub ? slqt_register(sub) : 0;
}

void slqt_be_subwindow_set_title(int64_t sub, const char* t)
{
    auto* s = qobject_cast<QMdiSubWindow*>((QObject*)slqt_resolve(sub));
    if (s && t) s->setWindowTitle(QString::fromUtf8(t));
}

void slqt_be_subwindow_show_maximized(int64_t sub)
{
    auto* s = qobject_cast<QMdiSubWindow*>((QObject*)slqt_resolve(sub));
    if (s) s->showMaximized();
}

/* ── 对话框（QDialog，BaseDialog 基类）────────────────────────────────── */

int64_t slqt_be_dialog_create(int64_t parent)
{
    QWidget* parentW = parent ? asWidget(parent) : nullptr;
    return slqt_register(new QDialog(parentW));
}

void slqt_be_dialog_set_modal(int64_t d, int32_t on)
{
    auto* dlg = qobject_cast<QDialog*>((QObject*)slqt_resolve(d));
    if (dlg) dlg->setModal(on != 0);
}

int32_t slqt_be_dialog_exec(int64_t d)
{
    auto* dlg = qobject_cast<QDialog*>((QObject*)slqt_resolve(d));
    return dlg ? (int32_t)dlg->exec() : 0;
}

void slqt_be_dialog_accept(int64_t d)
{
    auto* dlg = qobject_cast<QDialog*>((QObject*)slqt_resolve(d));
    if (dlg) dlg->accept();
}

void slqt_be_dialog_reject(int64_t d)
{
    auto* dlg = qobject_cast<QDialog*>((QObject*)slqt_resolve(d));
    if (dlg) dlg->reject();
}

/* ── 控件 min/max 尺寸（面板规格钳制落地到 Qt 原生）───────────────────── */

void slqt_be_widget_set_min_size(int64_t h, int32_t w, int32_t hh)
{
    QWidget* o = asWidget(h);
    if (o) o->setMinimumSize(w, hh);
}

void slqt_be_widget_set_max_size(int64_t h, int32_t w, int32_t hh)
{
    QWidget* o = asWidget(h);
    if (o) o->setMaximumSize(w, hh);
}
