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

/* 2026-11-12 P2 能力扩展（Widgets 核心，非可选模块） */
#include <QFileDialog>
#include <QStatusBar>
#include <QTreeWidget>
#include <QTreeWidgetItem>
#include <QSplitter>
#include <QPlainTextEdit>
#include <QSyntaxHighlighter>
/* 2026-11-13 VS 多标签 */
#include <QTabWidget>
#include <QTextBlock>
#include <QTextCursor>
#include <QTextDocument>
#include <QRegularExpression>
#include <QPaintEvent>
#include <QMouseEvent>
#include <QScrollBar>
#include <QFont>
#include <QColor>
#include <QSet>
#include <QHash>
#include <QMap>
#include <QList>
#include <algorithm>

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

/* ── 2026-11-12 SLang 语法高亮 ──────────────────────────────────────────
 * QSyntaxHighlighter 派生类只覆盖 highlightBlock，不需要 Q_OBJECT/moc。
 * '#' 行注释优先；关键字/数字/字符串按正则逐块着色。 */
class SlangHighlighter : public QSyntaxHighlighter
{
public:
    explicit SlangHighlighter(QTextDocument* doc) : QSyntaxHighlighter(doc) {}
protected:
    void highlightBlock(const QString& text) override
    {
        QTextCharFormat kw, num, str, com;
        kw.setForeground(QColor("#7b1fa2")); kw.setFontWeight(QFont::Bold);
        num.setForeground(QColor("#b35900"));
        str.setForeground(QColor("#0a7d3f"));
        com.setForeground(QColor("#8a8f98")); com.setFontItalic(true);

        int comment = text.indexOf(QLatin1Char('#'));
        int limit = (comment >= 0) ? comment : text.length();
        QString code = text.left(limit);

        QRegularExpression kwRx(QStringLiteral("\\b(public|private|class|static|void|int|Int64|Int32|string|bool|float|double|ret|if|elif|else|while|break|continue|import|new|null|true|false|try|catch|label|this|extends|namespace)\\b"));
        auto ki = kwRx.globalMatch(code);
        while (ki.hasNext()) { auto m = ki.next(); setFormat(m.capturedStart(), m.capturedLength(), kw); }

        QRegularExpression numRx(QStringLiteral("\\b[0-9]+\\b"));
        auto ni = numRx.globalMatch(code);
        while (ni.hasNext()) { auto m = ni.next(); setFormat(m.capturedStart(), m.capturedLength(), num); }

        QRegularExpression strRx(QStringLiteral("\"[^\"]*\""));
        auto si = strRx.globalMatch(code);
        while (si.hasNext()) { auto m = si.next(); setFormat(m.capturedStart(), m.capturedLength(), str); }

        if (comment >= 0) setFormat(comment, text.length() - comment, com);
    }
};

/* ── 2026-11-12 QCodeEdit 复合控件 ───────────────────────────────────────
 * QPlainTextEdit + 行号/断点装订线 + 当前行高亮 + 光标行回调；
 * 全部用 paintEvent/mousePressEvent 覆盖与 lambda 连接，无需 moc。 */
class SlangCodeEdit : public QPlainTextEdit
{
public:
    QSet<int> breakpoints;
    QSet<int> boundLines;   /* 已被调试会话 verified 的行 → 实心红点 */
    int stoppedLine = 0;    /* 当前停驻行 → 装订线箭头 + 行高亮 */
    int64_t lineCb = 0;
    int64_t bpCb = 0;
    int64_t lineSlot = 0;
    int64_t bpSlot = 0;
    SlangHighlighter* highlighter = nullptr;
    int m_gutter = 0;

    explicit SlangCodeEdit(QWidget* parent = nullptr) : QPlainTextEdit(parent)
    {
        setLineWrapMode(QPlainTextEdit::NoWrap);
        QFont f(QStringLiteral("Consolas"));
        f.setPointSize(10);
        setFont(f);
        m_gutter = gutterWidth();
        setViewportMargins(m_gutter, 0, 0, 0);
        QObject::connect(this, &QPlainTextEdit::cursorPositionChanged, [this]() {
            markCurrentLine();
            if (lineCb)
                ((void (*)(int64_t, int64_t))lineCb)(lineSlot, (int64_t)(textCursor().blockNumber() + 1));
        });
        markCurrentLine();
    }

    int gutterWidth() const
    {
        int digits = 1;
        int maxLine = qMax(1, blockCount());
        while (maxLine >= 10) { maxLine /= 10; ++digits; }
        return 18 + fontMetrics().horizontalAdvance(QLatin1Char('9')) * digits + 12;
    }

    /* QAbstractScrollArea::setViewportMargins 为 protected：
     * 只在派生类内部重算装订线宽度，后端函数通过本方法触发。 */
    void syncGutter()
    {
        m_gutter = gutterWidth();
        setViewportMargins(m_gutter, 0, 0, 0);
        viewport()->update();
    }

    void markCurrentLine()
    {
        QList<QTextEdit::ExtraSelection> sels;
        if (!isReadOnly())
        {
            QTextEdit::ExtraSelection sel;
            sel.format.setBackground(QColor("#f2f6fc"));
            sel.format.setProperty(QTextFormat::FullWidthSelection, true);
            sel.cursor = textCursor();
            sel.cursor.clearSelection();
            sels.append(sel);
        }
        setExtraSelections(sels);
    }

protected:
    void paintEvent(QPaintEvent* e) override
    {
        int gw = gutterWidth();
        if (m_gutter != gw) { m_gutter = gw; setViewportMargins(gw, 0, 0, 0); }
        QPlainTextEdit::paintEvent(e);

        QPainter p(viewport());
        QRect r = e->rect();
        p.fillRect(QRect(0, r.top(), gw, r.height()), QColor("#f4f6f8"));
        p.setPen(QColor("#c8d0da"));
        p.drawLine(gw - 1, r.top(), gw - 1, r.bottom());

        QTextBlock block = firstVisibleBlock();
        int blockNumber = block.blockNumber();
        int top = (int)blockBoundingGeometry(block).translated(contentOffset()).top();
        int bottom = top + (int)blockBoundingRect(block).height();
        p.setFont(font());
        while (block.isValid() && top <= r.bottom())
        {
            if (block.isVisible() && bottom >= r.top())
            {
                int line = blockNumber + 1;
                if (breakpoints.contains(line))
                {
                    if (boundLines.contains(line))
                    {
                        p.setBrush(QColor("#e5484d"));
                        p.setPen(Qt::NoPen);
                    }
                    else
                    {
                        p.setBrush(Qt::NoBrush);
                        p.setPen(QPen(QColor("#e5484d"), 1.5));
                    }
                    p.drawEllipse(3, top + 3, 9, 9);
                }
                if (line == stoppedLine)
                {
                    int rowH = (int)blockBoundingRect(block).height();
                    p.fillRect(QRect(gw, top, qMax(0, viewport()->width() - gw), rowH),
                               QColor(245, 166, 35, 45));
                    p.setPen(QPen(QColor("#f5a623"), 2));
                    p.drawLine(gw - 4, top + 2, gw - 4, top + rowH - 2);
                    p.drawLine(gw - 4, top + 2, gw - 10, top + 7);
                    p.drawLine(gw - 4, top + rowH - 2, gw - 10, top + rowH - 7);
                }
                p.setPen(QColor("#8a94a6"));
                p.drawText(14, top, gw - 18, fontMetrics().height(),
                           Qt::AlignRight, QString::number(line));
            }
            block = block.next();
            top = bottom;
            bottom = top + (int)blockBoundingRect(block).height();
            ++blockNumber;
        }
    }

    void mousePressEvent(QMouseEvent* e) override
    {
        if (e->button() == Qt::LeftButton && e->position().x() < m_gutter)
        {
            QTextCursor c = cursorForPosition(QPoint(m_gutter + 1, (int)e->position().y()));
            int line = c.blockNumber() + 1;
            if (breakpoints.contains(line)) breakpoints.remove(line);
            else breakpoints.insert(line);
            viewport()->update();
            if (bpCb) ((void (*)(int64_t, int64_t))bpCb)(bpSlot, (int64_t)line);
            e->accept();
            return;
        }
        QPlainTextEdit::mousePressEvent(e);
    }
};

/* 树节点按「句柄 → 路径前缀 → item」缓存；SL 侧只传路径字符串。 */
static QHash<int64_t, QMap<QString, QTreeWidgetItem*> > g_tree_nodes;

static QString slqt_tree_item_path(QTreeWidgetItem* item)
{
    return item ? item->data(0, Qt::UserRole).toString() : QString();
}

/* 本模块的 QPlainTextEdit 一律由 slqt_be_codeedit_create 创建，
 * 因此可安全地下转到 SlangCodeEdit（避免依赖 RTTI / 无 Q_OBJECT 的 qobject_cast）。 */
static SlangCodeEdit* asCode(int64_t h)
{
    QObject* o = (QObject*)slqt_resolve(h);
    QPlainTextEdit* pe = qobject_cast<QPlainTextEdit*>(o);
    if (!pe) return nullptr;
    return static_cast<SlangCodeEdit*>(pe);
}

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
/* SLangRender renderTexture 通道：ptr = RGBA8 top-down 像素块
 * (w*h*4)。构造 QImage（wrap 不拷贝）-> fromImage（拷贝）-> setPixmap，
 * scaledContents 让 label 随窗口缩放；qobject_cast 过滤非 QLabel 句柄。 */
int32_t slqt_be_label_set_pixmap_rgba(int64_t h, int64_t ptr, int32_t w, int32_t hh)
{
    auto* o = qobject_cast<QLabel*>((QObject*)slqt_resolve(h));
    if (!o || !ptr || w <= 0 || hh <= 0) return 0;
    QImage img((const uchar*)(uintptr_t)ptr, w, hh, (qsizetype)w * 4, QImage::Format_RGBA8888);
    if (img.isNull()) return 0;
    o->setPixmap(QPixmap::fromImage(img));
    o->setScaledContents(true);
    return 1;
}
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
    /* 2026-11-12 P2 扩展信号 */
    case SLQT_SIG_TREE_SELECTED:
        if (auto* t = qobject_cast<QTreeWidget*>(sender))
            QObject::connect(t, &QTreeWidget::itemSelectionChanged, [=]() {
                QByteArray b = slqt_tree_item_path(t->currentItem()).toUtf8();
                ((void (*)(int64_t, const char*))dispatchCb)(slot, b.constData());
            });
        break;
    case SLQT_SIG_CODEEDIT_LINE_CHANGED:
        if (auto* e = asCode(h)) { e->lineCb = dispatchCb; e->lineSlot = slot; }
        break;
    case SLQT_SIG_CODEEDIT_BREAKPOINT:
        if (auto* e = asCode(h)) { e->bpCb = dispatchCb; e->bpSlot = slot; }
        break;
    /* 2026-11-13 VS 多标签：两个 int 载荷信号 */
    case SLQT_SIG_TAB_CHANGED:
        if (auto* t = qobject_cast<QTabWidget*>(sender))
            QObject::connect(t, &QTabWidget::currentChanged, [=](int idx) {
                ((void (*)(int64_t, int64_t))dispatchCb)(slot, (int64_t)idx);
            });
        break;
    case SLQT_SIG_TAB_CLOSE_REQUESTED:
        if (auto* t = qobject_cast<QTabWidget*>(sender))
            QObject::connect(t, &QTabWidget::tabCloseRequested, [=](int idx) {
                ((void (*)(int64_t, int64_t))dispatchCb)(slot, (int64_t)idx);
            });
        break;
    /* 2026-11-13 第十四轮 右键菜单：控件构造时已设 CustomContextMenu 策略 */
    case SLQT_SIG_TAB_CONTEXT:
        if (auto* t = qobject_cast<QTabWidget*>(sender))
            QObject::connect(t, &QWidget::customContextMenuRequested, [=](const QPoint& pos) {
                int idx = t->tabBar()->tabAt(pos);
                ((void (*)(int64_t, int64_t))dispatchCb)(slot, (int64_t)idx);
            });
        break;
    case SLQT_SIG_TREE_CONTEXT:
        if (auto* t = qobject_cast<QTreeWidget*>(sender))
            QObject::connect(t, &QWidget::customContextMenuRequested, [=](const QPoint& pos) {
                QTreeWidgetItem* it = t->itemAt(pos);
                if (it) t->setCurrentItem(it);
                QByteArray b = slqt_tree_item_path(it).toUtf8();
                ((void (*)(int64_t, const char*))dispatchCb)(slot, b.constData());
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

/* 2026-11-13 第十四轮：独立弹出菜单（parent=nullptr，配合 popup_exec） */
int64_t slqt_be_menu_create_popup(const char* title)
{
    QString t = QString::fromUtf8(title ? title : "");
    return slqt_register(new QMenu(nullptr));
}

/* 阻塞弹出：anchor 控件 (x,y) 局部坐标 → mapToGlobal 后 exec。
 * 返回被选中 QAction 的登记句柄（未选中/取消返回 0）。 */
int64_t slqt_be_menu_popup_exec(int64_t menu, int64_t anchor, int32_t x, int32_t y)
{
    auto* m = qobject_cast<QMenu*>((QObject*)slqt_resolve(menu));
    if (!m) return 0;
    QWidget* w = anchor ? asWidget(anchor) : nullptr;
    QPoint gp(x, y);
    if (w) gp = w->mapToGlobal(gp);
    QAction* sel = m->exec(gp);
    return sel ? slqt_register(sel) : 0;
}

void slqt_be_action_set_text(int64_t a, const char* t)
{
    auto* act = qobject_cast<QAction*>((QObject*)slqt_resolve(a));
    if (act && t) act->setText(QString::fromUtf8(t));
}

void slqt_be_action_set_enabled(int64_t a, int64_t on)
{
    auto* act = qobject_cast<QAction*>((QObject*)slqt_resolve(a));
    if (act) act->setEnabled(on != 0);
}

int64_t slqt_be_action_enabled(int64_t a)
{
    auto* act = qobject_cast<QAction*>((QObject*)slqt_resolve(a));
    return (act && act->isEnabled()) ? (int64_t)1 : (int64_t)0;
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

/* ========================================================================
 * 2026-11-12 P2 能力扩展实现（QFileDialog / QStatusBar / QTreeWidget /
 * QSplitter / QCodeEdit）。均为 Widgets 核心能力，不依赖可选 Qt 模块。
 * ======================================================================== */

/* ── QFileDialog：模态静态调用，返回选中路径；取消为空串 ──────────────── */
const char* slqt_be_filedialog_open(const char* dir, const char* filter)
{
    QString s = QFileDialog::getOpenFileName(nullptr, QStringLiteral("Open"),
        QString::fromUtf8(dir ? dir : ""), QString::fromUtf8(filter ? filter : ""));
    return slqt_put(g_text_buf, sizeof(g_text_buf), s.toUtf8());
}

const char* slqt_be_filedialog_save(const char* dir, const char* filter)
{
    QString s = QFileDialog::getSaveFileName(nullptr, QStringLiteral("Save As"),
        QString::fromUtf8(dir ? dir : ""), QString::fromUtf8(filter ? filter : ""));
    return slqt_put(g_text_buf, sizeof(g_text_buf), s.toUtf8());
}

const char* slqt_be_filedialog_dir(const char* dir)
{
    QString s = QFileDialog::getExistingDirectory(nullptr, QStringLiteral("Select Directory"),
        QString::fromUtf8(dir ? dir : ""));
    return slqt_put(g_text_buf, sizeof(g_text_buf), s.toUtf8());
}

/* ── QStatusBar：主窗口原生状态条 ─────────────────────────────────────── */
int64_t slqt_be_statusbar_create(int64_t parent)
{
    QWidget* p = parent ? asWidget(parent) : nullptr;
    return slqt_register(new QStatusBar(p));
}

void slqt_be_mainwindow_set_statusbar(int64_t win, int64_t sb)
{
    auto* w = qobject_cast<QMainWindow*>((QObject*)slqt_resolve(win));
    auto* s = qobject_cast<QStatusBar*>((QObject*)slqt_resolve(sb));
    if (w && s) w->setStatusBar(s);
}

void slqt_be_statusbar_show_message(int64_t sb, const char* t)
{
    auto* s = qobject_cast<QStatusBar*>((QObject*)slqt_resolve(sb));
    if (s) s->showMessage(QString::fromUtf8(t ? t : ""), 0);
}

void slqt_be_statusbar_add_widget(int64_t sb, int64_t w)
{
    auto* s = qobject_cast<QStatusBar*>((QObject*)slqt_resolve(sb));
    QWidget* widget = asWidget(w);
    if (s && widget) s->addWidget(widget);
}

/* ── QTreeWidget：路径式建模 ──────────────────────────────────────────── */
int64_t slqt_be_tree_create(int64_t parent)
{
    QWidget* p = parent ? asWidget(parent) : nullptr;
    QTreeWidget* t = new QTreeWidget(p);
    t->setColumnCount(1);
    t->setContextMenuPolicy(Qt::CustomContextMenu);
    return slqt_register(t);
}

void slqt_be_tree_set_header(int64_t h, const char* t)
{
    auto* tree = qobject_cast<QTreeWidget*>((QObject*)slqt_resolve(h));
    if (tree) tree->setHeaderLabel(QString::fromUtf8(t ? t : ""));
}

void slqt_be_tree_clear(int64_t h)
{
    auto* tree = qobject_cast<QTreeWidget*>((QObject*)slqt_resolve(h));
    if (tree) tree->clear();
    if (g_tree_nodes.contains(h)) g_tree_nodes[h].clear();
}

void slqt_be_tree_add_path(int64_t h, const char* path)
{
    auto* tree = qobject_cast<QTreeWidget*>((QObject*)slqt_resolve(h));
    if (!tree || !path) return;
    QStringList parts = QString::fromUtf8(path).split(QLatin1Char('/'), Qt::SkipEmptyParts);
    QString acc;
    QTreeWidgetItem* parentItem = nullptr;
    QMap<QString, QTreeWidgetItem*>& nodes = g_tree_nodes[h];
    for (int i = 0; i < parts.size(); ++i)
    {
        acc = acc.isEmpty() ? parts.at(i) : acc + QLatin1Char('/') + parts.at(i);
        auto it = nodes.constFind(acc);
        if (it != nodes.constEnd()) { parentItem = it.value(); continue; }
        QTreeWidgetItem* item = nullptr;
        if (parentItem) item = new QTreeWidgetItem(parentItem, QStringList() << parts.at(i));
        else            item = new QTreeWidgetItem(tree,      QStringList() << parts.at(i));
        item->setData(0, Qt::UserRole, acc);
        item->setExpanded(true);
        nodes.insert(acc, item);
        parentItem = item;
    }
}

int32_t slqt_be_tree_count(int64_t h)
{
    if (!g_tree_nodes.contains(h)) return 0;
    return (int32_t)g_tree_nodes[h].size();
}

const char* slqt_be_tree_selected_path(int64_t h)
{
    auto* tree = qobject_cast<QTreeWidget*>((QObject*)slqt_resolve(h));
    if (!tree) return g_text_buf[0] = '\0', g_text_buf;
    return slqt_put(g_text_buf, sizeof(g_text_buf),
                    slqt_tree_item_path(tree->currentItem()).toUtf8());
}

/* ── QSplitter：尺寸比例 ──────────────────────────────────────────────── */
int64_t slqt_be_splitter_create(int64_t parent, int32_t vertical)
{
    QWidget* p = parent ? asWidget(parent) : nullptr;
    return slqt_register(new QSplitter(vertical ? Qt::Vertical : Qt::Horizontal, p));
}

void slqt_be_splitter_add_widget(int64_t sp, int64_t w)
{
    auto* s = qobject_cast<QSplitter*>((QObject*)slqt_resolve(sp));
    QWidget* widget = asWidget(w);
    if (s && widget) s->addWidget(widget);
}

void slqt_be_splitter_set_sizes(int64_t sp, int32_t a, int32_t b, int32_t c)
{
    auto* s = qobject_cast<QSplitter*>((QObject*)slqt_resolve(sp));
    if (!s) return;
    QList<int> sizes;
    if (a > 0) sizes.append(a);
    if (b > 0) sizes.append(b);
    if (c > 0) sizes.append(c);
    if (!sizes.isEmpty()) s->setSizes(sizes);
}

/* ── QCodeEdit 复合控件 ───────────────────────────────────────────────── */
int64_t slqt_be_codeedit_create(int64_t parent)
{
    QWidget* p = parent ? asWidget(parent) : nullptr;
    return slqt_register(new SlangCodeEdit(p));
}

void slqt_be_codeedit_set_text(int64_t h, const char* t)
{
    SlangCodeEdit* e = asCode(h);
    if (e) e->setPlainText(QString::fromUtf8(t ? t : ""));
}

const char* slqt_be_codeedit_text(int64_t h)
{
    SlangCodeEdit* e = asCode(h);
    if (!e) return g_big_buf[0] = '\0', g_big_buf;
    return slqt_put(g_big_buf, sizeof(g_big_buf), e->toPlainText().toUtf8());
}

void slqt_be_codeedit_set_readonly(int64_t h, int32_t on)
{
    SlangCodeEdit* e = asCode(h);
    if (e) { e->setReadOnly(on != 0); e->markCurrentLine(); }
}

void slqt_be_codeedit_goto_line(int64_t h, int32_t line)
{
    SlangCodeEdit* e = asCode(h);
    if (!e) return;
    QTextBlock b = e->document()->findBlockByNumber(qMax(0, line - 1));
    QTextCursor c(b);
    e->setTextCursor(c);
    e->centerCursor();
}

int32_t slqt_be_codeedit_cursor_line(int64_t h)
{
    SlangCodeEdit* e = asCode(h);
    return e ? (int32_t)(e->textCursor().blockNumber() + 1) : 1;
}

void slqt_be_codeedit_set_highlight(int64_t h, int32_t on)
{
    SlangCodeEdit* e = asCode(h);
    if (!e) return;
    if (on)
    {
        if (!e->highlighter) e->highlighter = new SlangHighlighter(e->document());
        else e->highlighter->setDocument(e->document());
    }
    else if (e->highlighter)
    {
        e->highlighter->setDocument(nullptr);
    }
}

void slqt_be_codeedit_set_breakpoint(int64_t h, int32_t line, int32_t on)
{
    SlangCodeEdit* e = asCode(h);
    if (!e || line <= 0) return;
    if (on) e->breakpoints.insert(line);
    else    e->breakpoints.remove(line);
    e->viewport()->update();
}

int32_t slqt_be_codeedit_toggle_breakpoint(int64_t h)
{
    SlangCodeEdit* e = asCode(h);
    if (!e) return 0;
    int line = (int)(e->textCursor().blockNumber() + 1);
    if (e->breakpoints.contains(line)) { e->breakpoints.remove(line); e->viewport()->update(); return 0; }
    e->breakpoints.insert(line);
    e->viewport()->update();
    return 1;
}

void slqt_be_codeedit_clear_breakpoints(int64_t h)
{
    SlangCodeEdit* e = asCode(h);
    if (e) { e->breakpoints.clear(); e->viewport()->update(); }
}

const char* slqt_be_codeedit_breakpoints(int64_t h)
{
    SlangCodeEdit* e = asCode(h);
    if (!e) return g_text_buf[0] = '\0', g_text_buf;
    QList<int> v = e->breakpoints.values();
    std::sort(v.begin(), v.end());
    QString s;
    for (int i = 0; i < v.size(); ++i)
    {
        if (i) s += QLatin1Char(',');
        s += QString::number(v.at(i));
    }
    return slqt_put(g_text_buf, sizeof(g_text_buf), s.toUtf8());
}

void slqt_be_codeedit_set_font_pt(int64_t h, int32_t pt)
{
    SlangCodeEdit* e = asCode(h);
    if (!e || pt < 6 || pt > 72) return;
    QFont f = e->font();
    f.setPointSize(pt);
    e->setFont(f);
    e->syncGutter();
}

/* 光标下单词 / 选中文本：符号索引与「转到定义」的语义输入。 */
const char* slqt_be_codeedit_word(int64_t h)
{
    SlangCodeEdit* e = asCode(h);
    if (!e) return g_text_buf[0] = '\0', g_text_buf;
    QTextCursor c = e->textCursor();
    c.select(QTextCursor::WordUnderCursor);
    return slqt_put(g_text_buf, sizeof(g_text_buf), c.selectedText().toUtf8());
}

const char* slqt_be_codeedit_selected(int64_t h)
{
    SlangCodeEdit* e = asCode(h);
    if (!e) return g_text_buf[0] = '\0', g_text_buf;
    return slqt_put(g_text_buf, sizeof(g_text_buf), e->textCursor().selectedText().toUtf8());
}

/* ── SLDP TCP 客户端桥（2026-11-12 第四轮）──────────────────────────────
 * 背景：C VM 的 socket Option A 挂起协议在 Qt 事件回调重入 VM 时拿不到
 * 返回值（Net.Tcp.connectTimeout 返回 null），所以调试会话的 TCP IO 放在
 * Qt 原生层：readyRead 只在 C++ 侧把字节追加到缓冲，SL 侧经 poll 同步
 * 取走，全程不涉及 VM 协程挂起。QTcpSocket 头文件就近包含以保持改动集中。
 * ========================================================================== */
#include <QTcpSocket>

static QTcpSocket* g_sldp_sock = nullptr;
static QByteArray  g_sldp_inbox;

int32_t slqt_be_sldp_connect(int32_t port)
{
    slqt_be_sldp_close();
    g_sldp_sock = new QTcpSocket(nullptr);
    QObject::connect(g_sldp_sock, &QTcpSocket::readyRead, []() {
        if (g_sldp_sock) g_sldp_inbox.append(g_sldp_sock->readAll());
    });
    g_sldp_sock->connectToHost(QStringLiteral("127.0.0.1"), (quint16)port);
    return 1;
}

void slqt_be_sldp_send(const char* utf8)
{
    if (!g_sldp_sock || !utf8) return;
    g_sldp_sock->write(QByteArray(utf8));
    g_sldp_sock->flush();
}

const char* slqt_be_sldp_poll(void)
{
    QByteArray chunk = g_sldp_inbox;
    g_sldp_inbox.clear();
    return slqt_put(g_big_buf, sizeof(g_big_buf), chunk);
}

int32_t slqt_be_sldp_connected(void)
{
    if (!g_sldp_sock) return 0;
    return g_sldp_sock->state() == QAbstractSocket::ConnectedState ? 1 : 0;
}

void slqt_be_sldp_close(void)
{
    if (g_sldp_sock)
    {
        g_sldp_sock->disconnectFromHost();
        g_sldp_sock->deleteLater();
        g_sldp_sock = nullptr;
    }
    g_sldp_inbox.clear();
}

/* ── 2026-11-12 第五轮：断点确认态 / 停驻行 ───────────────────────────
 * csv 是已 verified 的 1-based 行号（逗号分隔）；空串 = 会话未起，点全空心。
 * stoppedLine=0 清箭头。两者只改绘制状态，不改用户设置的断点集合。 */
void slqt_be_codeedit_set_bound(int64_t h, const char* csv)
{
    SlangCodeEdit* e = asCode(h);
    if (!e) return;
    e->boundLines.clear();
    if (csv)
    {
        QList<QByteArray> parts = QByteArray(csv).split(',');
        for (const QByteArray& part : parts)
        {
            bool ok = false;
            int line = part.trimmed().toInt(&ok);
            if (ok && line > 0) e->boundLines.insert(line);
        }
    }
    e->viewport()->update();
}

void slqt_be_codeedit_set_stopped(int64_t h, int32_t line)
{
    SlangCodeEdit* e = asCode(h);
    if (!e) return;
    e->stoppedLine = line;
    e->viewport()->update();
}

/* ── QTabWidget：VS 式多标签文档区（2026-11-13） ────────────────────────
 * 说明：removeTab 不 delete 页面 QWidget（Qt 只解除父子关系）。页面对象由
 * SL 侧持有句柄并在关闭标签时显式 delete()，避免 C++/SL 双重释放。 */
static QTabWidget* asTab(int64_t h)
{
    return qobject_cast<QTabWidget*>(asWidget(h));
}

int64_t slqt_be_tab_create(int64_t parent)
{
    QWidget* p = parent ? asWidget(parent) : nullptr;
    QTabWidget* t = new QTabWidget(p);
    t->setDocumentMode(true);
    t->setMovable(true);
    t->setTabsClosable(true);
    t->setContextMenuPolicy(Qt::CustomContextMenu);
    return slqt_register(t);
}

int32_t slqt_be_tab_add(int64_t h, int64_t page, const char* title)
{
    QTabWidget* t = asTab(h);
    QWidget* w = page ? asWidget(page) : nullptr;
    if (!t || !w) return -1;
    return (int32_t)t->addTab(w, QString::fromUtf8(title ? title : ""));
}

int32_t slqt_be_tab_count(int64_t h)
{
    QTabWidget* t = asTab(h);
    return t ? (int32_t)t->count() : 0;
}

int32_t slqt_be_tab_current(int64_t h)
{
    QTabWidget* t = asTab(h);
    return t ? (int32_t)t->currentIndex() : -1;
}

void slqt_be_tab_set_current(int64_t h, int32_t idx)
{
    QTabWidget* t = asTab(h);
    if (t && idx >= 0 && idx < t->count()) t->setCurrentIndex(idx);
}

const char* slqt_be_tab_text(int64_t h, int32_t idx)
{
    QTabWidget* t = asTab(h);
    if (!t || idx < 0 || idx >= t->count()) return "";
    return slqt_put(g_text_buf, sizeof(g_text_buf), t->tabText(idx).toUtf8());
}

void slqt_be_tab_set_text(int64_t h, int32_t idx, const char* title)
{
    QTabWidget* t = asTab(h);
    if (!t || idx < 0 || idx >= t->count()) return;
    t->setTabText(idx, QString::fromUtf8(title ? title : ""));
}

void slqt_be_tab_remove(int64_t h, int32_t idx)
{
    QTabWidget* t = asTab(h);
    if (!t || idx < 0 || idx >= t->count()) return;
    t->removeTab(idx);
}

void slqt_be_tab_clear(int64_t h)
{
    QTabWidget* t = asTab(h);
    if (!t) return;
    while (t->count() > 0) t->removeTab(0);
}

void slqt_be_tab_set_closable(int64_t h, int32_t on)
{
    QTabWidget* t = asTab(h);
    if (t) t->setTabsClosable(on != 0);
}
