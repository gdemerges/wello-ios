---
title: Wello — Fiches App Store (8 langues)
statut: prêt à saisir dans App Store Connect
---

# Fiches App Store — Wello

Source unique des textes à saisir dans App Store Connect. **Vérifiées par
`docs/store/verifier-metadata.py`** (limites Apple : nom 30, sous-titre 30, mots-clés 100,
texte promo 170, description 4000).

## Règles appliquées

- **Le nom porte les mots-clés.** `Wello` seul a un volume de recherche nul : le champ *nom* est
  le signal de ranking le plus fort de l'App Store, il ne doit pas être gaspillé sur une marque
  inconnue. D'où `Wello: Eau & Hydratation`.
- **Nom, sous-titre et mots-clés sont les seuls champs indexés.** La description ne l'est pas :
  elle sert à convertir, pas à ranker. Ne pas y bourrer de mots-clés.
- **Aucune répétition** entre nom, sous-titre et mots-clés : un mot indexé une fois compte autant
  qu'un mot indexé trois fois, et les caractères sont rares.
- **Mots-clés séparés par des virgules sans espace** (un espace après la virgule consomme un
  caractère pour rien).
- **Aucune marque concurrente** dans les mots-clés (motif de rejet 5.2.1).
- Chaque locale a **son propre index** : c'est pour ça que les 8 fiches valent l'effort — c'est le
  levier ASO le moins cher de tous.

---

## 🇫🇷 Français (fr — langue de base)

- **Nom** : `Wello: Eau & Hydratation`
- **Sous-titre** : `Rappel d'eau et suivi santé`
- **Mots-clés** : `boire,verre,litre,hydrater,soif,tracker,journal,objectif,quotidien,sport,widget,montre,local`
- **Texte promotionnel** : `Un objectif d'hydratation calculé pour vous — pas une règle générique. Sans compte, sans pub, rien ne quitte votre iPhone.`

**Description :**

```
Combien d'eau vous faut-il aujourd'hui ? Pas « 8 verres ». Pas votre poids multiplié par un chiffre trouvé au hasard. Votre chiffre à vous, recalculé chaque jour.

Wello part des apports de référence de l'EFSA (l'autorité européenne de sécurité des aliments), puis ajuste votre objectif selon ce qui change vraiment vos besoins : l'énergie que vous avez dépensée aujourd'hui, la température ressentie là où vous êtes, l'altitude, et votre situation (grossesse, allaitement, besoin rénal).

CE QUI REND WELLO DIFFÉRENT

• Un calcul que vous pouvez vérifier. Chaque ligne de votre objectif est tappable : elle vous montre d'où vient le chiffre et sur quelle source scientifique il repose. Aucune autre app d'hydratation ne s'expose comme ça.

• 100 % local. Pas de compte à créer. Pas de publicité. Pas de traceur. Aucun serveur ne détient vos données, parce qu'il n'y a pas de serveur : tout vit sur votre iPhone.

• Tout l'écosystème Apple. Widgets d'écran d'accueil et de verrouillage, Live Activity, app Apple Watch autonome avec complication de cadran, Siri, Spotlight, bouton Action, Centre de contrôle. Ajoutez un verre sans ouvrir l'app.

• Santé. Wello lit votre activité pour ajuster l'objectif et écrit vos prises dans l'app Santé. Refusez n'importe quelle autorisation : l'app reste entièrement utilisable en saisie manuelle.

GRATUIT, POUR DE BON

Le cœur de Wello est gratuit et le reste : le calcul personnalisé, la saisie, la jauge, les rappels, les widgets et l'app Watch. Pas de version bridée.

WELLO+ (optionnel)

• Historique illimité
• Analyses et tendances
• Rappels adaptatifs, calés sur vos vrais creux
• Boissons personnalisées (café, thé, alcool… comptés à leur juste valeur)
• Export CSV
• Thèmes de couleur et icônes alternatives

7 jours d'essai gratuit. Abonnement annuel, ou paiement unique à vie — au choix.

ACCESSIBILITÉ

VoiceOver, Dynamic Type, Reduce Motion et contraste sont traités dans toute l'app, pas seulement sur l'écran principal.

—

Wello donne un repère fondé sur les apports de référence EFSA. Ce n'est pas un dispositif médical et cela ne remplace pas l'avis d'un professionnel de santé.
```

---

## 🇬🇧 English (en-US / en-GB)

- **Nom** : `Wello: Water & Hydration`
- **Sous-titre** : `Water reminder & drink log`
- **Mots-clés** : `drink,intake,tracker,daily,goal,glass,bottle,thirst,health,fitness,widget,watch,private`
- **Texte promotionnel** : `A hydration goal calculated for you — not a generic rule. No account, no ads, nothing ever leaves your iPhone.`

**Description :**

```
How much water do you actually need today? Not "8 glasses". Not your weight times some number someone made up. Your number, recalculated every day.

Wello starts from EFSA reference intakes (the European Food Safety Authority), then adjusts your goal for what genuinely changes your needs: the energy you burned today, the apparent temperature where you are, altitude, and your situation (pregnancy, breastfeeding, kidney stones).

WHAT MAKES WELLO DIFFERENT

• A calculation you can audit. Every line of your goal is tappable: it shows where the number comes from and which scientific source it rests on. No other hydration app opens its books like this.

• 100% on-device. No account. No ads. No trackers. No server holds your data, because there is no server: everything lives on your iPhone.

• The whole Apple ecosystem. Home Screen and Lock Screen widgets, Live Activity, a standalone Apple Watch app with a watch face complication, Siri, Spotlight, Action button, Control Center. Log a glass without opening the app.

• Health. Wello reads your activity to adjust the goal and writes your intake to the Health app. Deny any permission you like: the app stays fully usable with manual entry.

FREE, FOR REAL

Wello's core is free and stays free: the personalized calculation, logging, the gauge, reminders, widgets and the Watch app. No crippled version.

WELLO+ (optional)

• Unlimited history
• Analytics and trends
• Adaptive reminders, tuned to when you actually forget
• Custom drinks (coffee, tea, alcohol… counted for what they're worth)
• CSV export
• Color themes and alternate app icons

7-day free trial. Yearly subscription, or a one-time lifetime purchase — your call.

ACCESSIBILITY

VoiceOver, Dynamic Type, Reduce Motion and contrast are handled throughout the app, not just on the main screen.

—

Wello provides guidance based on EFSA reference intakes. It is not a medical device and does not replace advice from a healthcare professional.
```

---

## 🇪🇸 Español (es-ES / es-MX)

- **Nom** : `Wello: Agua e Hidratación`
- **Sous-titre** : `Recordatorio de beber agua`
- **Mots-clés** : `hidratar,vaso,litro,registro,diario,meta,sed,salud,deporte,widget,reloj,privado`
- **Texte promotionnel** : `Un objetivo de hidratación calculado para ti, no una regla genérica. Sin cuenta, sin anuncios, nada sale de tu iPhone.`

**Description :**

```
¿Cuánta agua necesitas hoy? No "8 vasos". No tu peso multiplicado por un número inventado. Tu cifra, recalculada cada día.

Wello parte de las ingestas de referencia de la EFSA (Autoridad Europea de Seguridad Alimentaria) y ajusta tu objetivo según lo que de verdad cambia tus necesidades: la energía que has gastado hoy, la sensación térmica donde estás, la altitud y tu situación (embarazo, lactancia, necesidad renal).

QUÉ HACE DIFERENTE A WELLO

• Un cálculo que puedes verificar. Cada línea de tu objetivo se puede tocar: te muestra de dónde sale la cifra y en qué fuente científica se apoya.

• 100 % local. Sin cuenta. Sin publicidad. Sin rastreadores. Ningún servidor guarda tus datos, porque no hay servidor: todo vive en tu iPhone.

• Todo el ecosistema Apple. Widgets de pantalla de inicio y bloqueo, Live Activity, app independiente para Apple Watch con complicación, Siri, Spotlight, botón de Acción y Centro de Control.

• Salud. Wello lee tu actividad para ajustar el objetivo y escribe tus tomas en la app Salud. Puedes denegar cualquier permiso: la app sigue siendo plenamente utilizable a mano.

GRATIS DE VERDAD

El núcleo de Wello es gratuito y lo seguirá siendo: cálculo personalizado, registro, indicador, recordatorios, widgets y app de Watch.

WELLO+ (opcional)

• Historial ilimitado
• Análisis y tendencias
• Recordatorios adaptativos
• Bebidas personalizadas (café, té, alcohol…)
• Exportación CSV
• Temas de color e iconos alternativos

7 días de prueba gratis. Suscripción anual o pago único de por vida.

—

Wello ofrece una referencia basada en las ingestas de la EFSA. No es un producto sanitario ni sustituye el consejo de un profesional de la salud.
```

---

## 🇩🇪 Deutsch (de-DE)

- **Nom** : `Wello: Wasser & Trinken`
- **Sous-titre** : `Trinkerinnerung & Tracker`
- **Mots-clés** : `hydration,glas,liter,tagesziel,durst,gesundheit,sport,protokoll,widget,uhr,privat`
- **Texte promotionnel** : `Ein Trinkziel, das für dich berechnet wird — keine Faustregel. Kein Konto, keine Werbung, nichts verlässt dein iPhone.`

**Description :**

```
Wie viel Wasser brauchst du heute wirklich? Nicht "8 Gläser". Nicht dein Gewicht mal irgendeine Zahl. Deine Zahl, jeden Tag neu berechnet.

Wello geht von den EFSA-Referenzwerten aus (Europäische Behörde für Lebensmittelsicherheit) und passt dein Ziel an das an, was deinen Bedarf tatsächlich verändert: die heute verbrauchte Energie, die gefühlte Temperatur an deinem Ort, die Höhe und deine Situation (Schwangerschaft, Stillzeit, Nierenbedarf).

WAS WELLO ANDERS MACHT

• Eine nachprüfbare Berechnung. Jede Zeile deines Ziels ist antippbar: Sie zeigt, woher die Zahl kommt und auf welcher wissenschaftlichen Quelle sie beruht.

• 100 % lokal. Kein Konto. Keine Werbung. Keine Tracker. Kein Server hält deine Daten, denn es gibt keinen Server: alles bleibt auf deinem iPhone.

• Das ganze Apple-Ökosystem. Widgets für Home- und Sperrbildschirm, Live Activity, eigenständige Apple-Watch-App mit Komplikation, Siri, Spotlight, Action Button und Kontrollzentrum.

• Health. Wello liest deine Aktivität für das Ziel und schreibt deine Einträge in die Health-App. Du kannst jede Berechtigung ablehnen — die App bleibt per Handeingabe voll nutzbar.

WIRKLICH KOSTENLOS

Der Kern von Wello ist und bleibt kostenlos: personalisierte Berechnung, Eingabe, Anzeige, Erinnerungen, Widgets und Watch-App.

WELLO+ (optional)

• Unbegrenzter Verlauf
• Auswertungen und Trends
• Adaptive Erinnerungen
• Eigene Getränke (Kaffee, Tee, Alkohol…)
• CSV-Export
• Farbthemen und alternative App-Symbole

7 Tage gratis testen. Jahresabo oder einmaliger Kauf für immer.

—

Wello liefert einen Richtwert auf Basis der EFSA-Referenzwerte. Es ist kein Medizinprodukt und ersetzt keine ärztliche Beratung.
```

---

## 🇮🇹 Italiano (it)

- **Nom** : `Wello: Acqua e Idratazione`
- **Sous-titre** : `Promemoria per bere acqua`
- **Mots-clés** : `idratarsi,bicchiere,litro,diario,obiettivo,sete,salute,sport,widget,orologio,privato`
- **Texte promotionnel** : `Un obiettivo di idratazione calcolato per te, non una regola generica. Nessun account, nessuna pubblicità, niente lascia il tuo iPhone.`

**Description :**

```
Quanta acqua ti serve oggi? Non "8 bicchieri". Non il tuo peso moltiplicato per un numero inventato. La tua cifra, ricalcolata ogni giorno.

Wello parte dai valori di riferimento EFSA (Autorità europea per la sicurezza alimentare) e adatta il tuo obiettivo a ciò che cambia davvero il fabbisogno: l'energia consumata oggi, la temperatura percepita dove ti trovi, l'altitudine e la tua situazione (gravidanza, allattamento, necessità renali).

COSA RENDE WELLO DIVERSO

• Un calcolo verificabile. Ogni riga del tuo obiettivo è toccabile: mostra da dove viene il numero e su quale fonte scientifica si basa.

• 100 % locale. Nessun account. Nessuna pubblicità. Nessun tracciante. Nessun server conserva i tuoi dati, perché non c'è alcun server: tutto resta sul tuo iPhone.

• Tutto l'ecosistema Apple. Widget per schermata Home e di blocco, Live Activity, app autonoma per Apple Watch con complicazione, Siri, Spotlight, tasto Azione e Centro di Controllo.

• Salute. Wello legge la tua attività per adattare l'obiettivo e scrive le assunzioni nell'app Salute. Puoi negare qualsiasi permesso: l'app resta pienamente utilizzabile a mano.

GRATIS SUL SERIO

Il cuore di Wello è gratuito e lo resta: calcolo personalizzato, registrazione, indicatore, promemoria, widget e app per Watch.

WELLO+ (opzionale)

• Cronologia illimitata
• Analisi e tendenze
• Promemoria adattivi
• Bevande personalizzate (caffè, tè, alcol…)
• Esportazione CSV
• Temi di colore e icone alternative

7 giorni di prova gratuita. Abbonamento annuale o acquisto unico a vita.

—

Wello fornisce un riferimento basato sui valori EFSA. Non è un dispositivo medico e non sostituisce il parere di un professionista sanitario.
```

---

## 🇧🇷 Português do Brasil (pt-BR)

- **Nom** : `Wello: Água e Hidratação`
- **Sous-titre** : `Lembrete de beber água`
- **Mots-clés** : `hidratar,copo,litro,registro,diário,meta,sede,saúde,esporte,widget,relógio,privado`
- **Texte promotionnel** : `Uma meta de hidratação calculada para você, não uma regra genérica. Sem conta, sem anúncios, nada sai do seu iPhone.`

**Description :**

```
Quanta água você precisa hoje? Não "8 copos". Não o seu peso multiplicado por um número qualquer. O seu número, recalculado todo dia.

O Wello parte das ingestões de referência da EFSA (Autoridade Europeia para a Segurança dos Alimentos) e ajusta sua meta ao que realmente muda a necessidade: a energia gasta hoje, a sensação térmica onde você está, a altitude e a sua situação (gravidez, amamentação, necessidade renal).

O QUE TORNA O WELLO DIFERENTE

• Um cálculo que você pode conferir. Cada linha da sua meta é tocável: mostra de onde vem o número e em qual fonte científica ele se apoia.

• 100 % local. Sem conta. Sem anúncios. Sem rastreadores. Nenhum servidor guarda seus dados, porque não existe servidor: tudo fica no seu iPhone.

• Todo o ecossistema Apple. Widgets na tela de início e de bloqueio, Live Activity, app independente para Apple Watch com complicação, Siri, Spotlight, botão de Ação e Central de Controle.

• Saúde. O Wello lê sua atividade para ajustar a meta e grava suas doses no app Saúde. Você pode negar qualquer permissão: o app continua totalmente utilizável manualmente.

GRATUITO DE VERDADE

O núcleo do Wello é gratuito e continua assim: cálculo personalizado, registro, medidor, lembretes, widgets e app do Watch.

WELLO+ (opcional)

• Histórico ilimitado
• Análises e tendências
• Lembretes adaptativos
• Bebidas personalizadas (café, chá, álcool…)
• Exportação CSV
• Temas de cor e ícones alternativos

7 dias de teste grátis. Assinatura anual ou compra única vitalícia.

—

O Wello oferece uma referência baseada nas ingestões da EFSA. Não é um dispositivo médico e não substitui a orientação de um profissional de saúde.
```

---

## 🇯🇵 日本語 (ja)

- **Nom** : `Wello: 水分補給トラッカー`
- **Sous-titre** : `水を飲むリマインダーと記録`
- **Mots-clés** : `飲水,健康,習慣,目標,ダイエット,運動,ウィジェット,ウォッチ,通知,コップ,水筒,熱中症,カフェイン,ヘルスケア,アラーム,飲み物`
- **Texte promotionnel** : `あなたのために計算された水分目標。アカウント不要、広告なし、データはiPhoneから出ません。`

**Description :**

```
今日、あなたに必要な水分はどれくらい？「コップ8杯」ではありません。体重に適当な数字を掛けたものでもありません。あなたの数字を、毎日計算し直します。

Wello は EFSA（欧州食品安全機関）の基準摂取量を出発点に、必要量を実際に左右する要素で目標を調整します。今日消費したエネルギー、いまいる場所の体感温度、標高、そしてあなたの状況（妊娠、授乳、腎臓の事情）。

WELLO が違う理由

• 検証できる計算。目標の各行はタップでき、その数字の出どころと科学的根拠を示します。

• 100 % 端末内で完結。アカウント不要。広告なし。トラッカーなし。サーバーがデータを持つことはありません。そもそもサーバーが存在しないからです。

• Apple エコシステム全体に対応。ホーム画面／ロック画面ウィジェット、Live Activity、単体で動く Apple Watch アプリと文字盤コンプリケーション、Siri、Spotlight、アクションボタン、コントロールセンター。

• ヘルスケア連携。活動量を読み取って目標を調整し、飲んだ量をヘルスケアに書き込みます。どの許可を拒否しても、手入力でフル機能のまま使えます。

本当に無料

Wello の中核は無料のままです。パーソナライズされた計算、記録、ゲージ、リマインダー、ウィジェット、Watch アプリ。

WELLO+（任意）

• 無制限の履歴
• 分析とトレンド
• 適応型リマインダー
• カスタムドリンク（コーヒー、お茶、アルコールなど）
• CSV 書き出し
• カラーテーマと代替アイコン

7日間無料。年額プラン、または買い切りをお選びいただけます。

—

Wello は EFSA の基準摂取量に基づく目安を示すものです。医療機器ではなく、医療専門家の助言に代わるものではありません。
```

---

## 🇨🇳 简体中文 (zh-Hans)

- **Nom** : `Wello: 喝水提醒与记录`
- **Sous-titre** : `每日饮水量追踪与目标`
- **Mots-clés** : `补水,水杯,健康,习惯,运动,减肥,小组件,手表,通知,升,渴,水壶,打卡,统计,健身,养生,定时,毫升`
- **Texte promotionnel** : `为你计算的饮水目标，而非通用规则。无需账号、没有广告，数据不离开你的 iPhone。`

**Description :**

```
你今天到底需要喝多少水？不是"8 杯"。也不是体重乘以某个随口说出的数字。是属于你的数字，每天重新计算。

Wello 以 EFSA（欧洲食品安全局）的参考摄入量为起点，再根据真正影响需求的因素调整你的目标：今天消耗的能量、你所在位置的体感温度、海拔，以及你的具体情况（怀孕、哺乳、肾脏需求）。

WELLO 的不同之处

• 可以核查的计算。目标的每一行都可以点按，告诉你这个数字从何而来、依据哪一份科学来源。

• 100% 本地。无需账号。没有广告。没有追踪器。没有服务器保存你的数据，因为根本不存在服务器：一切都留在你的 iPhone 上。

• 完整的 Apple 生态。主屏幕与锁定屏幕小组件、实时活动、独立的 Apple Watch App 与表盘复杂功能、Siri、Spotlight、操作按钮、控制中心。

• 健康。Wello 读取你的活动量来调整目标，并把饮水记录写入"健康"App。你可以拒绝任何权限：手动记录下，App 依然完整可用。

真正免费

Wello 的核心永远免费：个性化计算、记录、水位指示、提醒、小组件和 Watch App。

WELLO+（可选）

• 无限历史记录
• 分析与趋势
• 自适应提醒
• 自定义饮品（咖啡、茶、酒精等）
• CSV 导出
• 配色主题与备选图标

7 天免费试用。年度订阅，或一次性买断。

—

Wello 提供的是基于 EFSA 参考摄入量的参考值。它不是医疗器械，也不能替代健康专业人士的建议。
```

---

## 📸 Plan de captures d'écran

L'ordre compte : sur la page produit, seules les **2-3 premières** sont vues. Chaque capture porte
un **bandeau de texte** au-dessus de l'appareil — une capture brute ne convertit pas.

| # | Écran | Bandeau (fr) | Bandeau (en) |
|---|---|---|---|
| 1 | Accueil, jauge à ~70 % | **Votre objectif, pas une moyenne** | **Your goal, not an average** |
| 2 | Détail de l'objectif (BreakdownCard déplié) | **Chaque millilitre est justifié** | **Every milliliter, explained** |
| 3 | Écran Confidentialité / Méthode | **Aucun compte. Aucune pub. Rien ne sort de l'iPhone.** | **No account. No ads. Nothing leaves your iPhone.** |
| 4 | Widgets + Live Activity | **Un verre sans ouvrir l'app** | **Log a glass without opening the app** |
| 5 | Apple Watch + complication | **Au poignet, même hors ligne** | **On your wrist, even offline** |
| 6 | Analyses / tendances | **Vos habitudes, dans le temps** | **Your habits, over time** |

À produire : iPhone 6,9" (obligatoire) + Apple Watch. L'iPad est hors périmètre
(`TARGETED_DEVICE_FAMILY = 1`), donc aucune capture iPad n'est exigée.

## 📝 Notes pour App Review

```
Wello fonctionne intégralement sans compte : il n'y a rien à connecter.

HealthKit : l'app lit l'énergie active (pour ajuster l'objectif d'hydratation) et les prises
d'eau/alcool déjà enregistrées, et écrit les prises saisies dans Wello. Sur simulateur, aucune
donnée de santé n'existe : l'objectif retombe alors sur la base EFSA seule, ce qui est le
comportement attendu. Tous les refus d'autorisation sont gérés — l'app reste pleinement
utilisable en saisie manuelle.

Localisation : utilisée uniquement pour interroger Open-Meteo (température ressentie et
altitude). Position approximative, transmise le temps de la requête, jamais stockée hors de
l'appareil.

Achats : Wello+ est un abonnement annuel OU un achat unique à vie ; l'un ou l'autre suffit.
« Restaurer mes achats » est présent sur le paywall.

Cadre non médical : l'app affiche un repère fondé sur les apports de référence EFSA (2010).
Le disclaimer apparaît en fin d'onboarding et dans l'écran « Méthode ».
```

## 🔁 Après la publication

L'ASO se **teste**. Deux leviers gratuits à utiliser :

- **Custom Product Pages** (jusqu'à 35) : mêmes binaires, captures et textes différents, chacune
  avec son URL — utile pour tester l'angle « scientifique » contre l'angle « confidentialité ».
- **Product Page Optimization** : A/B test natif de l'icône, des captures et de la vidéo. **C'est
  le seul moyen honnête de savoir si une icône marche mieux qu'une autre** — à lancer dès qu'il y
  a assez de trafic.
