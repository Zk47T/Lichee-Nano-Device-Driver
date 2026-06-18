# Upstreaming the ADS1220 driver

The series lives in `patches/mainline-ads1220/`:
```
0000-cover-letter.patch
0001-dt-bindings-iio-adc-Add-TI-ADS1220.patch     # binding first
0002-iio-adc-Add-TI-ADS1220-driver.patch          # driver + Kconfig/Makefile/MAINTAINERS
```
State: `checkpatch.pl --strict` clean (0002: 0/0/0), `dt_binding_check` + `dtbs_check`
pass, builds `W=1` with no warnings, and it is hardware-tested on an Allwinner F1C100s
(Lichee Pi Nano) reading a potentiometer.

## Update 2026-06-13 — plan change: wait for David Lechner's ADS122C14, likely share a driver

David Lechner (BayLibre, core IIO reviewer) replied: he has a TI ADS122C14 series
(same wiring family, superset of features) going to the list ~next week and suggests
adding the ADS1220 onto that rather than maintaining separate files. His binding
points (two DRDY pins via interrupt-names [drdy, dout-drdy] + dout-drdy-gpios fallback;
ref0-supply/ref1-supply naming for REFx0/REFx1; per-channel reference selection;
clocks for the external clock; RDT excitation-current properties; allow any
diff-channels combination; channel limit is arbitrary, 12 valid) are mostly the shape
his more complete binding will already have.

Decision (user): hold the prepared v2, do NOT respin now. Reply to David accepting the
collaboration (reply draft: replies/reply-to-david-wait-collaborate.txt); revisit the
ADS1220 once the ADS122C14 series lands and either fold ADS1220 into it or follow its
structure. The v2 series below remains valid/buildable but is parked.

## Update 2026-06-12 — second review round folded in, v2 regenerated

New v1 feedback arrived from Andy Shevchenko (full driver review: includes,
time-unit constants, -ENOENT from datarate lookup, PM_RUNTIME_ACQUIRE guards,
in_range()/ARRAY_SIZE(), 0V vref question, no regmap clarification, etc.) and
Conor Dooley (diff-channels polarity question; block-style items preferred).
All folded into `patches/mainline-ads1220-v2/` together with the user's own
draft v2 (good catches adopted; its silent-probe-failure bug on a 0V vref,
missing validate_trigger, and unverifiable hand-written base-commit were
fixed/kept from the canonical version). togreg re-fetched 2026-06-12: tip is
still `ae696dfa4`, so the base is unchanged. MAINTAINERS entry moved to sit
after TI ADS1018 (matching the tree's actual neighbourhood). checkpatch
--strict 0/0/0 on both patches, dt_binding_check passes, x86-64 + ARM W=1
clean, git am onto base verified. Reply drafts for Jonathan (x2), Andy (x2)
and Conor are in `patches/mainline-ads1220-v2/replies/`. Fresh hardware
artifacts in `output-new/`.

## v1 sent and reviewed — v2 READY (2026-06-11)

v1 was sent to linux-iio on 2026-06-10 (msgid 20260610151342.44274-1-zizuzacker@gmail.com)
and reviewed by Jonathan Cameron (IIO maintainer), Andy Shevchenko, and the Sashiko bot.

v2 in `patches/mainline-ads1220-v2/` addresses every human review point and the valid
bot findings (see the per-patch "Changes in v2" changelogs). Highlights:
- scale read/write/available now share one runtime IIO_VAL_INT_PLUS_NANO table derived
  from vref, so values round-trip (Jonathan; also kills the bot's div-by-zero);
- offset reading negated per datasheet section 8.3.12 + IIO sign convention;
- spi_write_then_read() with stack buffers everywhere (no DMA-safe buffers needed);
- .validate_trigger = iio_validate_own_trigger (no pollable DRDY status on this chip);
- POWERDOWN on buffer postdisable so continuous mode stops;
- MAINTAINERS split across the two patches; channels 7 -> 12; datasheet link + DRDY
  note in the binding; avdd voltage only read when used as the reference;
- cover letter answers Andy's "why a new driver" / datasheet questions and defers the
  RTD/IDAC binding scope with a concrete plan (adi,excitation-current-* style).

Bot findings rejected as false positives (with verification): onehot-vs-timestamp
(timestamp is not part of the scan mask), rx DMA alignment (moot - Jonathan also said
adjacent buffers work in practice), tx/rx locking (moot - stack buffers), debugfs needing
PM resume (interface and registers stay functional in power-down, section 8.4.3.4),
IRQF_NO_THREAD storm (DRDY is edge; same pattern as in-tree ti-ads1119).

Validation on jic23/iio togreg (base ae696dfa4): git am clean, x86-64 allmodconfig +
ARM W=1 builds clean, dt_binding_check passes, checkpatch --strict 0/0/0 on BOTH
patches. v2 artifacts rebuilt for the Lichee Pi Nano in output-new/ (the in-repo 7.0
tree needs one compat cast for the older IIO_CHAN_SOFT_TIMESTAMP macro; the upstream
patch does not).

Before sending v2: reply inline to Jonathan's and Andy's mails (drafts in
`patches/mainline-ads1220-v2/replies/`), retest on hardware if possible, then
`git send-email` the three `v2-*.patch` files to the same recipient list.

## Step 1 — Rebase onto the IIO development tree  [DONE]

The series in `patches/mainline-ads1220/` is now generated on top of Jonathan Cameron's
IIO tree (`jic23/iio` `togreg`), base commit `ae696dfa4` (Linux **7.1-rc6**), and carries
a `base-commit:` line so maintainers / `b4` apply it onto exactly that.

Verified on that tree:
- `git am` of both patches applied cleanly (no conflicts);
- `make allmodconfig` + `make W=1 drivers/iio/adc/ti-ads1220.o` compiles with **no
  warnings** (no API drift from the 7.0 dev kernel);
- `checkpatch.pl --strict`: 0002 = 0/0/0; 0001 = 1 warning (the standard "MAINTAINERS in
  the driver patch" false positive);
- `make dt_binding_check DT_SCHEMA_FILES=ti,ads1220.yaml` passes;
- `git apply --check` onto the base succeeds.

The clone used was:
```bash
git clone --depth 1 -b togreg \
  https://git.kernel.org/pub/scm/linux/kernel/git/jic23/iio.git iio-upstream
```
Before sending, `git fetch` it again and re-run the checks (togreg moves daily); if the
base has moved, re-run `git am` + `git format-patch --base=auto` to refresh the series.

## Step 2 — Configure git send-email (one time)

```bash
git config --global sendemail.smtpServer     smtp.gmail.com
git config --global sendemail.smtpEncryption tls
git config --global sendemail.smtpServerPort 587
git config --global sendemail.smtpUser       zizuzacker@gmail.com
# Gmail: use an App Password, not your normal password.
git config --global user.name  "Nguyen Minh Tien"
git config --global user.email "zizuzacker@gmail.com"
```
`From:` must equal your `Signed-off-by:` (both already
`Nguyen Minh Tien <zizuzacker@gmail.com>`).

## Step 3 — Send the series

Binding patch first, then driver. To = IIO maintainer; Cc = lists + reviewers
(from `scripts/get_maintainer.pl`):

```bash
git send-email \
  --to="Jonathan Cameron <jic23@kernel.org>" \
  --cc="linux-iio@vger.kernel.org" \
  --cc="devicetree@vger.kernel.org" \
  --cc="Rob Herring <robh@kernel.org>" \
  --cc="Krzysztof Kozlowski <krzk+dt@kernel.org>" \
  --cc="Conor Dooley <conor+dt@kernel.org>" \
  --cc="David Lechner <dlechner@baylibre.com>" \
  --cc="Nuno Sá <nuno.sa@analog.com>" \
  --cc="Andy Shevchenko <andy@kernel.org>" \
  --cc="linux-kernel@vger.kernel.org" \
  0000-cover-letter.patch 0001-*.patch 0002-*.patch
```
Tip: do a dry run first with `--dry-run`, and/or send the whole thing `--to` your own
address once to eyeball threading before the real send.

## Step 4 — Track and iterate

- Watch the thread on https://lore.kernel.org/linux-iio/ .
- Reviews usually take days–weeks. Reply inline, plain-text, no top-posting.
- Respin as v2: address every comment, then
  `git format-patch -v2 --cover-letter ...` and add a changelog under the `---`:
  ```
  ---
  Changes in v2:
   - <reviewer X>: ...
  ```
- Carry forward any `Reviewed-by:`/`Acked-by:` tags you receive.
- Consider `b4` (`b4 am`, `b4 prep`) — it automates fetching, threading and trailers.

## Things reviewers may raise (be ready to discuss)

- **scale-as-gain-reciprocal** convention for `_scale_available` (matches ti-ads1119;
  read returns absolute scale). They may prefer absolute available scales.
- **`ti,vref-avdd`** property — they may want the reference source modelled differently
  (e.g. a documented enum, or inferred). Be ready to justify or rework.
- **No-interrupt fallback** (fixed delay when DRDY isn't wired) — some prefer making the
  interrupt mandatory. Justify the single-shot delay path or gate features on the IRQ.
- Keep the binding patch and driver patch order; binding must pass `dt_binding_check`.
