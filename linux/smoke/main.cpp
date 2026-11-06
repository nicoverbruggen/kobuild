#include <QApplication>
#include <QFile>
#include <QLineEdit>
#include <QNetworkAccessManager>
#include <QSqlDatabase>
#include <QSqlQuery>
#include <QTest>
#include <private/qguiapplication_p.h>
#include <png.h>
#include <cstdio>

class CheckWidget : public QLineEdit
{
    Q_OBJECT
public:
    using QLineEdit::QLineEdit;
};

// Runs headless: widgets, simulated input, SQLite, resources and libpng.
int main(int argc, char **argv)
{
    QApplication app(argc, argv);
    QNetworkAccessManager network;
    CheckWidget widget;
    widget.show();
    QTest::keyClicks(&widget, QStringLiteral("kobuild"));
    auto database = QSqlDatabase::addDatabase(QStringLiteral("QSQLITE"));
    database.setDatabaseName(QStringLiteral(":memory:"));
    QSqlQuery query(database);
    QFile message(QStringLiteral(":/kobuild/message.txt"));
    const bool ok = widget.text() == QLatin1String("kobuild") && database.open()
            && query.exec(QStringLiteral("SELECT 1")) && query.next() && query.value(0).toInt() == 1
            && message.open(QIODevice::ReadOnly) && !message.readAll().isEmpty()
            && QGuiApplicationPrivate::platformIntegration() && png_access_version_number() > 0;
    std::printf("%s\n", ok ? "Qt Linux check passed" : "Qt Linux check failed");
    return ok ? 0 : 1;
}

#include "main.moc"
