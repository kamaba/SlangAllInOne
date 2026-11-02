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

#include <QString>
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

static QApplication* g_app = nullptr;
static char g_text_buf[8192];

static QWidget* asWidget(int64_t h) { return static_cast<QWidget*>((QObject*)slqt_resolve(h)); }

/* ── 应用 ─────────────────────────────────────────────────────────────── */
int64_t slqt_be_app_create(void)
{
    if (!g_app)
    {
        static int   argc = 1;
        static char  arg0[] = "slang_qt";
        static char* argv[] = { arg0, nullptr };
        g_app = new QApplication(argc, argv);
    }
    return slqt_register(g_app);
}

void slqt_be_app_set_style(const char* n) { if (g_app && n) g_app->setStyle(QString::fromUtf8(n)); }
void slqt_be_app_set_stylesheet(const char* c) { if (g_app && c) g_app->setStyleSheet(QString::fromUtf8(c)); }
void slqt_be_app_exec(void) { if (g_app) g_app->exec(); }
void slqt_be_app_process_events(void) { if (g_app) g_app->processEvents(); }
void slqt_be_app_quit(void) { if (g_app) g_app->quit(); }
int32_t slqt_be_app_argc(void) { return g_app ? (int32_t)g_app->argc() : 0; }

/* ── 对象 / 控件 ─────────────────────────────────────────────────────── */
void slqt_be_object_delete(int64_t h) { void* o = slqt_resolve(h); if (o) delete (QObject*)o; }
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
    if (auto* w = qobject_cast<QWidget*>(o)) { w->setWindowTitle(QString::fromUtf8(t)); }
}

const char* slqt_be_widget_text(int64_t h)
{
    QObject* o = (QObject*)slqt_resolve(h);
    if (!o) return "";
    if (auto* w = qobject_cast<QPushButton*>(o)) { QByteArray b = w->text().toUtf8(); snprintf(g_text_buf, sizeof(g_text_buf), "%s", b.constData()); return g_text_buf; }
    if (auto* w = qobject_cast<QLabel*>(o)) { QByteArray b = w->text().toUtf8(); snprintf(g_text_buf, sizeof(g_text_buf), "%s", b.constData()); return g_text_buf; }
    if (auto* w = qobject_cast<QLineEdit*>(o)) { QByteArray b = w->text().toUtf8(); snprintf(g_text_buf, sizeof(g_text_buf), "%s", b.constData()); return g_text_buf; }
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
    default:
        break;
    }
    return 1;
}
