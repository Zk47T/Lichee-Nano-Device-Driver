// SPDX-License-Identifier: GPL-2.0
#include <linux/module.h>
#include <linux/platform_device.h>
#include <linux/gpio/consumer.h>
#include <linux/interrupt.h>
#include <linux/of.h>

struct btn_led_dev {
	struct gpio_desc *btn;
	struct gpio_desc *led;
	int irq;
};

static irqreturn_t btn_isr(int irq, void *data)
{
	struct btn_led_dev *dev = data;

	/* gpiod_get_value() đã xử lý ACTIVE_LOW: trả về 1 khi nhấn, 0 khi thả */
	gpiod_set_value(dev->led, !gpiod_get_value(dev->btn));
	return IRQ_HANDLED;
}

static int btn_led_probe(struct platform_device *pdev)
{
	struct btn_led_dev *dev;
	int ret;

	dev = devm_kzalloc(&pdev->dev, sizeof(*dev), GFP_KERNEL);
	if (!dev)
		return -ENOMEM;

	dev->btn = devm_gpiod_get(&pdev->dev, "btn", GPIOD_IN);
	if (IS_ERR(dev->btn))
		return dev_err_probe(&pdev->dev, PTR_ERR(dev->btn),
				     "failed to get btn gpio\n");

	dev->led = devm_gpiod_get(&pdev->dev, "led", GPIOD_OUT_LOW);
	if (IS_ERR(dev->led))
		return dev_err_probe(&pdev->dev, PTR_ERR(dev->led),
				     "failed to get led gpio\n");

	dev->irq = gpiod_to_irq(dev->btn);
	if (dev->irq < 0)
		return dev_err_probe(&pdev->dev, dev->irq,
				     "failed to get irq\n");

	ret = devm_request_irq(&pdev->dev, dev->irq, btn_isr,
			       IRQF_TRIGGER_RISING | IRQF_TRIGGER_FALLING,
			       "btn_led", dev);
	if (ret)
		return dev_err_probe(&pdev->dev, ret,
				     "failed to request irq\n");

	platform_set_drvdata(pdev, dev);
	dev_info(&pdev->dev, "loaded, irq=%d\n", dev->irq);
	return 0;
}

static const struct of_device_id btn_led_of_match[] = {
	{ .compatible = "mydriver,btn-led" },
	{}
};
MODULE_DEVICE_TABLE(of, btn_led_of_match);

static struct platform_driver btn_led_driver = {
	.probe = btn_led_probe,
	.driver = {
		.name		= "btn_led",
		.of_match_table	= btn_led_of_match,
	},
};
module_platform_driver(btn_led_driver);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Zk47T");
MODULE_DESCRIPTION("Button interrupt controls LED");
