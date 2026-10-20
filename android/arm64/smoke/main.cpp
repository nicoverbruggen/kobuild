#include <QApplication>
#include <QNetworkAccessManager>
#include <QSensor>
#include <QWidget>

class CheckWidget : public QWidget {
    Q_OBJECT
public:
    using QWidget::QWidget;
};

int main(int argc, char **argv)
{
    QApplication app(argc, argv);
    QNetworkAccessManager network;
    QSensor sensor("accelerometer");
    CheckWidget widget;
    widget.show();
    return app.exec();
}

#include "main.moc"
