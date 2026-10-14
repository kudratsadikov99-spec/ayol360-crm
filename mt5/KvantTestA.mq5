//+------------------------------------------------------------------+
//|  KvantTestA.mq5 - TEST A: signal sifati, martingeylsiz         |
//|  v3: SCALPING + NAZORATLI MARTINGEYL (SETKA). YUQORI XAVF!       |
//|  - Signal SignalTF da (standart M5), grafik TF ahamiyatsiz:      |
//|    trend bozorida EMA pullback, range bozorida Bollinger + RSI.  |
//|  - Kichik sof foydada yopish: Quick / Money / Basket / Dynamic   |
//|    TP. Foyda = profit + svop + komissiya (spred narxda bor).     |
//|  - Foyda bilan yopilgach yangi signal bo'lsa - qayta kirish.     |
//|  - Har juftlikda BUY va SELL savatlari alohida (hedging hisob).  |
//|  - Martingeyl: narx setka masofasiga qarshi ketsa lot x          |
//|    Multiplier, eng ko'pi MaxMartingaleSteps. Savatdagi barcha    |
//|    pozitsiyalarda bitta umumiy qattiq server SL.                 |
//|  - Hisob limitlari barcha nusxalar uchun umumiy (global o'zg.).  |
//|  - Bir juftlikda faqat bitta nusxa yangi savdo ochadi.           |
//+------------------------------------------------------------------+
#property copyright   "KvantMartinUz"
#property version     "3.00"
#property description "TEST A: signal sifati, martingeylsiz. Faqat Strategiya Testeri uchun."

#include <Trade\Trade.mqh>

#define KMU_PREFIX "KMU3_"
#define ATR_DAVR   14

enum ENUM_REJIM
  {
   REJIM_CUSTOM       = 0, // Custom: quyidagi qiymatlar
   REJIM_CONSERVATIVE = 1, // 1 - Conservative
   REJIM_BALANCED     = 2, // 2 - Balanced
   REJIM_AGGRESSIVE   = 3, // 3 - Aggressive Scalping
   REJIM_SIGNAL_TEST  = 4  // 4 - Signal testi (martingeylsiz, add-on siz)
  };

enum ENUM_LOT_MODE
  {
   LOT_FIXED       = 0, // Belgilangan InitialLot
   LOT_SERIES_RISK = 1  // Butun seriya xavfi bo'yicha (SeriesRiskPercent)
  };

//+------------------------------------------------------------------+
//| Kirish parametrlari. (*) belgili qiymatlar Custom bo'lmagan       |
//| rejimda rejimning o'zidan olinadi.                                |
//+------------------------------------------------------------------+
input group "=== Rejim ==="
input ENUM_REJIM      Rejim                       = REJIM_SIGNAL_TEST; // Rejim ((*) qiymatlar rejimdan olinadi)

input group "=== Signal ==="
input ENUM_TIMEFRAMES SignalTF                    = PERIOD_M5;  // (*) Signal timeframe
input bool            UseTrendSignals             = true;       // Trend bozori: EMA pullback signali
input bool            UseRangeSignals             = true;       // Range bozori: Bollinger + RSI signali
input int             EmaFast                     = 20;         // Tez EMA
input int             EmaSlow                     = 50;         // Sekin EMA
input int             AdxPeriod                   = 14;         // ADX davri
input double          AdxTrendLevel               = 22.0;       // (*) ADX shundan yuqori = trend, past = range
input double          PullbackATR                 = 0.5;        // (*) Trend: sham tez EMA ga shu ATR ichida yaqinlashsa
input int             BBPeriod                    = 20;         // Bollinger davri
input double          BBDeviation                 = 2.0;        // Bollinger og'ishi
input int             RsiPeriod                   = 7;          // RSI davri
input double          RsiBuyLevel                 = 35.0;       // (*) Range: BUY uchun RSI shundan past
input double          RsiSellLevel                = 65.0;       // (*) Range: SELL uchun RSI shundan yuqori
input int             EntryWindowSeconds          = 0;          // Sham ochilgach kirish oynasi, soniya (0 = butun sham)
input int             MaxEntriesPerBar            = 1;          // (*) Bitta signal shamidan eng ko'p yangi kirish

input group "=== Take Profit ==="
input double          TPATRKoef                   = 0.6;   // (*) Dynamic TP = ATR(SignalTF) x shu
input int             MinTPPoints                 = 30;    // Minimal TP, punkt
input int             MaxTPPoints                 = 0;     // Maksimal TP, punkt (0 = cheksiz)
input double          MinTPSpreadKoef             = 3.0;   // TP kamida spred x shu
input double          QuickTPMoney                = 0.0;   // Quick TP: bitta pozitsiya sof foydasi, hisob valyutasida (0 = dinamik)
input double          MinNetProfitMoney           = 0.0;   // Har qanday foyda bilan yopishda minimal sof foyda
input bool            EnableBasketProfitClose     = true;  // Savat umumiy foydada birga yopilsin
input double          BasketTakeProfitMoney       = 0.0;   // Savat TP, hisob valyutasida (0 = dinamik)
input double          BasketTPKoef                = 1.0;   // (*) Dinamik savat TP = baza lot TP qiymati x shu
input bool            AllowNewEntryAfterProfitClose = true; // Foyda bilan yopilgach shu shamning o'zida yangi kirish
input bool            EnableReEntry               = true;  // Bitta signal shamidan qayta kirish (MaxEntriesPerBar gacha)
input int             ReEntryCooldownSeconds      = 60;    // (*) Foyda bilan yopilgach kutish, soniya
input int             MinHoldSeconds              = 30;    // Foyda bilan yopishdan oldin minimal ushlab turish, soniya
input int             MaxHoldHours                = 24;    // Savatni eng uzog'i bilan ushlab turish, soat (0 = cheksiz)

input group "=== Pozitsiyalar ==="
input bool            EnableMultiplePositions     = true;  // (*) Foyda tomonga qo'shimcha (add-on) kirishlar
input int             MaxPositionsPerSymbol       = 5;     // (*) Bitta juftlikda eng ko'p pozitsiya
input int             MaxTotalPositions           = 10;    // (*) Butun hisobda eng ko'p pozitsiya (barcha nusxalar)
input double          AddOnMinDistanceATR         = 0.5;   // Add-on: oxirgi kirishdan foyda tomonga kamida ATR x shu
input bool            AllowHedgeBaskets           = true;  // BUY va SELL savatlari bir vaqtda (faqat hedging)
input bool            AllowDuplicateInstances     = false; // Bitta juftlikda bir nechta nusxa savdo qilsin (TAVSIYA ETILMAYDI)

input group "=== Martingale ==="
input bool            EnableMartingale            = true;  // (*) Martingeyl yoqilgan
input ENUM_LOT_MODE   LotMode                     = LOT_SERIES_RISK; // Boshlang'ich lot usuli
input double          InitialLot                  = 0.01;  // Boshlang'ich lot (LOT_FIXED)
input double          SeriesRiskPercent           = 8.0;   // (*) Butun seriya qattiq SL ga tegsa: balansning % (LOT_SERIES_RISK)
input double          MartingaleMultiplier        = 1.3;   // (*) Har bosqichda lot x shu
input int             MaxMartingaleSteps          = 3;     // (*) Qo'shimcha bosqichlar soni (0-9)
input int             GridStepPoints              = 100;   // Bosqichlar orasidagi minimal masofa, punkt
input bool            DynamicGridATR              = true;  // (*) Masofa = max(GridStepPoints, ATR(M15) x GridATRKoef)
input double          GridATRKoef                 = 1.2;   // (*) Dinamik setka koeffitsienti
input double          HardSLExtraATR              = 1.0;   // Oxirgi bosqichdan keyingi qattiq SL zaxirasi, ATR(M15) x
input int             MinStepSeconds              = 300;   // (*) Bosqichlar orasida minimal vaqt, soniya
input bool            RequireNewBarForStep        = true;  // Bosqich faqat oxirgi kirishdan keyingi yangi shamda
input bool            BlockStepAgainstStrongTrend = true;  // Kuchli qarshi trendda yangi bosqich ochilmasin
input double          AdxStrongLevel              = 35.0;  // Kuchli trend: ADX shundan yuqori
input double          MaxBasketLots               = 0.0;   // Savatdagi eng ko'p jami lot (0 = cheksiz)
input double          MaxBasketDrawdownPercent    = 10.0;  // Savatning eng yomon holat zarari / joriy zarari limiti, balans %
input double          MaxTotalExposure            = 0.0;   // Butun hisobda jami lot (0 = cheksiz)
input double          BasketStopLossMoney         = 0.0;   // Savat zarari shu summaga yetsa yopiladi (0 = o'chiq)

input group "=== Risk Management ==="
input double          MaxDailyLossPercent         = 10.0;  // Kunlik zarar: kun boshidagi equity dan % (0 = o'chiq)
input double          MaxEquityDrawdownPercent    = 30.0;  // Eng yuqori equity dan tushish % (0 = o'chiq)
input bool            StopTradingAfterLossLimit   = true;  // Limit buzilsa savdo to'xtaydi (kunlik - ertagacha, DD - qo'lda tiklaguncha)
input bool            EmergencyCloseOnLimit       = true;  // Limit buzilsa barcha pozitsiyalar yopiladi
input bool            ResetLimits                 = false; // true: to'xtash belgilari va eng yuqori equity tiklanadi
input int             MaxSpreadPoints             = 25;    // Maksimal spred, punkt (0 = o'chiq)
input double          MaxSpreadTPPercent          = 50.0;  // Spred TP masofasining shu % idan oshsa kirish yo'q
input int             MaxSlippagePoints           = 10;    // Maksimal sirpanish, punkt
input double          MinMarginLevel              = 300.0; // Margin level shundan past - yangi savdo yo'q, %
input double          EmergencyMarginLevel        = 150.0; // Margin level shundan past - hammasi yopiladi, % (0 = o'chiq)
input double          MinFreeMarginPercent        = 50.0;  // Savdodan keyin bo'sh marja equity ning kamida shu % i
input int             LossCooldownMinutes         = 30;    // Zarar bilan yopilgach shu juftlikda kutish, daqiqa

input group "=== Vaqt ==="
input int             TradeStartHour              = 0;     // Yangi savdo boshlanishi, server soati
input int             TradeEndHour                = 24;    // Yangi savdo tugashi, server soati
input bool            SkipRollover                = true;  // Rollover oralig'ida yangi savdo ochmaslik
input int             RolloverStartHour           = 23;    // Rollover boshlanishi, server soati
input int             RolloverEndHour             = 1;     // Rollover tugashi, server soati
input int             CloseFridayHour             = 20;    // Juma: shu soatda yopiladi (dam olishda yopiladigan bozorlar)

input group "=== Texnik ==="
input ulong           MagicBase                   = 3000000; // Magic asosi (barcha nusxalarda bir xil qoldiring)
input int             MagicOffset                 = 0;     // Magic qo'shimchasi, 0-999 (odatda 0)
input double          CommissionPerLot            = 0.0;   // Komissiya: 1 lot, ikki tomon, hisob valyutasida (0 = tarixdan)
input int             MaxRetries                  = 3;     // Xatoda urinishlar soni (1-5)
input bool            ShowPanel                   = true;  // Holatni grafikda ko'rsatish
input bool            LogReasons                  = true;  // Savdo ochilmaslik sababini jurnalga yozish

//+------------------------------------------------------------------+
//| Rejimga bog'liq ishchi sozlamalar                                |
//+------------------------------------------------------------------+
struct Sozlama
  {
   ENUM_TIMEFRAMES   tf;
   double            adxTrend;
   double            pullbackATR;
   double            rsiBuy;
   double            rsiSell;
   int               maxEntriesPerBar;
   double            tpATR;
   double            basketTPKoef;
   int               reEntryCooldown;
   bool              multiple;
   int               maxPerSymbol;
   int               maxTotal;
   bool              martin;
   double            seriesRisk;
   double            mult;
   int               maxSteps;
   bool              dynGrid;
   double            gridATR;
   int               minStepSec;
  };

//--- Bitta yo'nalishdagi savat (shu EA ning shu juftlikdagi pozitsiyalari)
struct Savat
  {
   int               dir;          // 1 = BUY, -1 = SELL
   int               soni;
   double            lotlar;
   double            sof;          // profit + svop + komissiya
   double            birinchiNarx;
   double            oxirgiNarx;
   datetime          birinchiVaqt;
   datetime          oxirgiVaqt;
   int               daraja;       // martingeyl darajasi (0 = boshlang'ich)
   double            bazaLot;
   double            sl;
  };

//+------------------------------------------------------------------+
//| Global o'zgaruvchilar                                            |
//+------------------------------------------------------------------+
CTrade   g_trade;
Sozlama  S;
ulong    g_magic          = 0;
bool     g_netting        = false;
double   g_token          = 0.0;

int      g_hEmaF          = INVALID_HANDLE;
int      g_hEmaS          = INVALID_HANDLE;
int      g_hAdx           = INVALID_HANDLE;
int      g_hRsi           = INVALID_HANDLE;
int      g_hBB            = INVALID_HANDLE;
int      g_hAtrS          = INVALID_HANDLE;
int      g_hAtr15         = INVALID_HANDLE;

datetime g_bar            = 0;
int      g_barSignal      = 0;
int      g_rejimNow       = 0;      // 1 = trend, 0 = range
int      g_trendDir       = 0;
double   g_adx            = 0.0;
double   g_atrS           = 0.0;
double   g_atr15          = 0.0;
int      g_entriesBar     = 0;

datetime g_lastProfitClose = 0;
datetime g_lastLossClose   = 0;

string   g_holat          = "";
string   g_logKalit       = "";
datetime g_logVaqt        = 0;
double   g_tpMaqsadB      = 0.0;
double   g_tpMaqsadS      = 0.0;

ulong    g_komId[];
double   g_komVal[];

int      g_maxSimul       = 0;
double   g_maxMarginUse   = 0.0;

//+------------------------------------------------------------------+
//| Yordamchi funksiyalar                                            |
//+------------------------------------------------------------------+
string GVNom(const string k) { return KMU_PREFIX + k; }

double GVGet(const string n, const double def)
  {
   return GlobalVariableCheck(n) ? GlobalVariableGet(n) : def;
  }

string NetNom(const string k) { return GVNom(StringFormat("net_%I64u_%s_%s", g_magic, _Symbol, k)); }

bool BizningMagic(const ulong m) { return (m >= MagicBase && m < MagicBase + 1000); }

datetime KunBoshi(const datetime t) { return (datetime)((long)t - (long)t % 86400); }

bool Bufer(const int h, const int buf, const int bosh, const int soni, double &arr[])
  {
   ArraySetAsSeries(arr, true);
   return (CopyBuffer(h, buf, bosh, soni, arr) == soni);
  }

int JoriySpred()
  {
   MqlTick t;
   if(!SymbolInfoTick(_Symbol, t))
      return INT_MAX;
   return (int)MathRound((t.ask - t.bid) / _Point);
  }

double NormNarx(const double narx)
  {
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(ts <= 0.0)
      ts = _Point;
   return NormalizeDouble(MathRound(narx / ts) * ts, _Digits);
  }

int LotRaqamlar(const double qadam)
  {
   int    d = 0;
   double s = qadam;
   while(s < 1.0 - 1e-9 && d < 8)
     {
      s *= 10.0;
      d++;
     }
   return d;
  }

//--- Lotni broker qadamiga keltirish. yaxlitlash=true: eng yaqin qadamga, aks holda pastga
double LotNorm(const double lot, const bool yaxlitlash)
  {
   double minL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double st   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(st <= 0.0)
      st = minL;
   double n = yaxlitlash ? MathRound(lot / st) : MathFloor(lot / st + 1e-9);
   double l = n * st;
   if(l < minL - 1e-12)
      return 0.0;
   if(l > maxL)
      l = maxL;
   return NormalizeDouble(l, LotRaqamlar(st));
  }

//--- 1 lot uchun narx 1.0 birlikka o'zgarganda pul qiymati
double NarxBirlikQiymati(const int dir)
  {
   MqlTick t;
   if(!SymbolInfoTick(_Symbol, t))
      return 0.0;
   double narx = (dir > 0) ? t.ask : t.bid;
   double d    = 1000.0 * _Point;
   double p    = 0.0;
   if(!OrderCalcProfit(dir > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, _Symbol, 1.0, narx,
                       dir > 0 ? narx - d : narx + d, p))
      return 0.0;
   return MathAbs(p) / d;
  }

//--- lot hajmi pts punkt harakatda qancha pul
double PulQiymat(const double lot, const double pts)
  {
   if(lot <= 0.0 || pts <= 0.0)
      return 0.0;
   return lot * pts * _Point * NarxBirlikQiymati(1);
  }

//--- Pozitsiya komissiyasi (manfiy son): ochilish komissiyasi x 2 yoki CommissionPerLot
double Komissiya(const ulong posId, const double hajm)
  {
   if(CommissionPerLot > 0.0)
      return -CommissionPerLot * hajm;
   int n = ArraySize(g_komId);
   for(int i = 0; i < n; i++)
      if(g_komId[i] == posId)
         return g_komVal[i];
   double c = 0.0;
   if(HistorySelectByPosition((long)posId))
     {
      int k = HistoryDealsTotal();
      for(int i = 0; i < k; i++)
        {
         ulong d = HistoryDealGetTicket(i);
         if(d == 0)
            continue;
         if(HistoryDealGetInteger(d, DEAL_ENTRY) == DEAL_ENTRY_IN)
            c += HistoryDealGetDouble(d, DEAL_COMMISSION) + HistoryDealGetDouble(d, DEAL_FEE);
        }
     }
   double natija = c * 2.0;
   if(n >= 200)
     {
      ArrayRemove(g_komId, 0, 100);
      ArrayRemove(g_komVal, 0, 100);
      n = ArraySize(g_komId);
     }
   ArrayResize(g_komId, n + 1);
   ArrayResize(g_komVal, n + 1);
   g_komId[n]  = posId;
   g_komVal[n] = natija;
   return natija;
  }

int IzohDaraja(const string iz)
  {
   int p = StringFind(iz, "|L");
   if(p < 0)
      return 0;
   return (int)StringToInteger(StringSubstr(iz, p + 2, 1));
  }

bool QaytaUrinish(const uint rc)
  {
   switch(rc)
     {
      case TRADE_RETCODE_REQUOTE:
      case TRADE_RETCODE_PRICE_CHANGED:
      case TRADE_RETCODE_PRICE_OFF:
      case TRADE_RETCODE_CONNECTION:
      case TRADE_RETCODE_TIMEOUT:
      case TRADE_RETCODE_TOO_MANY_REQUESTS:
         return true;
     }
   if(rc == 0 && !TerminalInfoInteger(TERMINAL_CONNECTED))
      return true;
   return false;
  }

void Sabab(const string kalit, const string matn)
  {
   g_holat = matn;
   if(!LogReasons || matn == "")
      return;
   if(MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE))
      return;
   datetime hozir = TimeCurrent();
   if(kalit == g_logKalit && hozir - g_logVaqt < 1800)
      return;
   if(kalit != g_logKalit && hozir - g_logVaqt < 60)
      return;
   g_logKalit = kalit;
   g_logVaqt  = hozir;
   Print("Holat: ", matn);
  }

//+------------------------------------------------------------------+
//| Rejim sozlamalari                                                |
//+------------------------------------------------------------------+
void RejimniQollash()
  {
   S.tf               = SignalTF;
   S.adxTrend         = AdxTrendLevel;
   S.pullbackATR      = PullbackATR;
   S.rsiBuy           = RsiBuyLevel;
   S.rsiSell          = RsiSellLevel;
   S.maxEntriesPerBar = MaxEntriesPerBar;
   S.tpATR            = TPATRKoef;
   S.basketTPKoef     = BasketTPKoef;
   S.reEntryCooldown  = ReEntryCooldownSeconds;
   S.multiple         = EnableMultiplePositions;
   S.maxPerSymbol     = MaxPositionsPerSymbol;
   S.maxTotal         = MaxTotalPositions;
   S.martin           = EnableMartingale;
   S.seriesRisk       = SeriesRiskPercent;
   S.mult             = MartingaleMultiplier;
   S.maxSteps         = MaxMartingaleSteps;
   S.dynGrid          = DynamicGridATR;
   S.gridATR          = GridATRKoef;
   S.minStepSec       = MinStepSeconds;

   switch(Rejim)
     {
      case REJIM_CONSERVATIVE:
         S.tf = PERIOD_M15;   S.adxTrend = 25.0; S.pullbackATR = 0.3; S.rsiBuy = 30.0; S.rsiSell = 70.0;
         S.maxEntriesPerBar = 1; S.tpATR = 0.8; S.basketTPKoef = 1.0; S.reEntryCooldown = 900;
         S.multiple = false;  S.maxPerSymbol = 3; S.maxTotal = 4;
         S.martin = true;     S.seriesRisk = 4.0; S.mult = 1.2; S.maxSteps = 2;
         S.dynGrid = true;    S.gridATR = 1.5;   S.minStepSec = 900;
         break;
      case REJIM_BALANCED:
         S.tf = PERIOD_M5;    S.adxTrend = 22.0; S.pullbackATR = 0.5; S.rsiBuy = 35.0; S.rsiSell = 65.0;
         S.maxEntriesPerBar = 1; S.tpATR = 0.6; S.basketTPKoef = 1.0; S.reEntryCooldown = 120;
         S.multiple = true;   S.maxPerSymbol = 4; S.maxTotal = 8;
         S.martin = true;     S.seriesRisk = 8.0; S.mult = 1.3; S.maxSteps = 3;
         S.dynGrid = true;    S.gridATR = 1.2;   S.minStepSec = 300;
         break;
      case REJIM_AGGRESSIVE:
         S.tf = PERIOD_M1;    S.adxTrend = 20.0; S.pullbackATR = 0.7; S.rsiBuy = 40.0; S.rsiSell = 60.0;
         S.maxEntriesPerBar = 2; S.tpATR = 0.8; S.basketTPKoef = 0.8; S.reEntryCooldown = 0;
         S.multiple = true;   S.maxPerSymbol = 5; S.maxTotal = 10;
         S.martin = true;     S.seriesRisk = 10.0; S.mult = 1.3; S.maxSteps = 3;
         S.dynGrid = true;    S.gridATR = 1.0;   S.minStepSec = 120;
         break;
      case REJIM_SIGNAL_TEST:
         // Balanced signali, lekin martingeyl va add-on o'chiq: signalning o'z sifatini tekshirish uchun
         S.tf = PERIOD_M5;    S.adxTrend = 22.0; S.pullbackATR = 0.5; S.rsiBuy = 35.0; S.rsiSell = 65.0;
         S.maxEntriesPerBar = 1; S.tpATR = 0.6; S.basketTPKoef = 1.0; S.reEntryCooldown = 120;
         S.multiple = false;  S.maxPerSymbol = 2; S.maxTotal = 4;
         S.martin = false;    S.seriesRisk = 2.0; S.mult = 1.0; S.maxSteps = 0;
         S.dynGrid = true;    S.gridATR = 1.2;   S.minStepSec = 300;
         break;
      default:
         break;
     }
  }

string RejimNomi()
  {
   switch(Rejim)
     {
      case REJIM_CONSERVATIVE: return "Conservative";
      case REJIM_BALANCED:     return "Balanced";
      case REJIM_AGGRESSIVE:   return "Aggressive";
      case REJIM_SIGNAL_TEST:  return "Signal testi";
     }
   return "Custom";
  }

//+------------------------------------------------------------------+
//| Masofalar                                                        |
//+------------------------------------------------------------------+
//--- ATR asosidagi TP (spred tagisiz) - spred filtri uchun
double TPXom()
  {
   double pts = (g_atrS > 0.0) ? g_atrS / _Point * S.tpATR : 0.0;
   if(MinTPPoints > 0)
      pts = MathMax(pts, (double)MinTPPoints);
   if(MaxTPPoints > 0)
      pts = MathMin(pts, (double)MaxTPPoints);
   return pts;
  }

//--- Ishchi TP, punkt: xarajatlardan aniq yuqori
double TPPunkt()
  {
   return MathMax(TPXom(), JoriySpred() * MinTPSpreadKoef);
  }

//--- Martingeyl bosqichlari orasidagi masofa (narx birligida)
double GridMasofa()
  {
   double g = GridStepPoints * _Point;
   if(S.dynGrid)
      g = MathMax(g, g_atr15 * S.gridATR);
   return MathMax(g, JoriySpred() * _Point * 4.0);
  }

//--- Birinchi kirishdan qattiq SL gacha masofa
double QattiqSLMasofa()
  {
   int steps = S.martin ? S.maxSteps : 0;
   return GridMasofa() * steps + g_atr15 * HardSLExtraATR;
  }

//+------------------------------------------------------------------+
//| Pozitsiyalarni sanash                                            |
//+------------------------------------------------------------------+
int PozSoni(const bool faqatBelgi)
  {
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0 || !BizningMagic((ulong)PositionGetInteger(POSITION_MAGIC)))
         continue;
      if(faqatBelgi && PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      n++;
     }
   return n;
  }

double JamiLot()
  {
   double l = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t != 0 && BizningMagic((ulong)PositionGetInteger(POSITION_MAGIC)))
         l += PositionGetDouble(POSITION_VOLUME);
     }
   return l;
  }

//+------------------------------------------------------------------+
//| Savatni yig'ish                                                  |
//+------------------------------------------------------------------+
void SavatYig(const int dir, Savat &s)
  {
   ZeroMemory(s);
   s.dir = dir;
   long oxirgiMsc   = 0;
   long birinchiMsc = LONG_MAX;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0)
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != g_magic)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      long typ = PositionGetInteger(POSITION_TYPE);
      if((dir > 0 && typ != POSITION_TYPE_BUY) || (dir < 0 && typ != POSITION_TYPE_SELL))
         continue;
      double vol  = PositionGetDouble(POSITION_VOLUME);
      double narx = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl   = PositionGetDouble(POSITION_SL);
      long   msc  = PositionGetInteger(POSITION_TIME_MSC);
      int    lvl  = IzohDaraja(PositionGetString(POSITION_COMMENT));
      double pr   = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      ulong  pid  = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
      pr += Komissiya(pid, vol);

      s.soni++;
      s.lotlar += vol;
      s.sof    += pr;
      if(lvl > s.daraja)
         s.daraja = lvl;
      if(lvl == 0 && s.bazaLot <= 0.0)
         s.bazaLot = vol;
      if(msc > oxirgiMsc)
        {
         oxirgiMsc    = msc;
         s.oxirgiNarx = narx;
         s.oxirgiVaqt = (datetime)(msc / 1000);
        }
      if(msc < birinchiMsc)
        {
         birinchiMsc    = msc;
         s.birinchiNarx = narx;
         s.birinchiVaqt = (datetime)(msc / 1000);
         s.sl           = sl;
        }
     }
   if(g_netting && s.soni > 0)
     {
      // netting: bitta pozitsiya, bosqich holati global o'zgaruvchilarda
      s.daraja = (int)GVGet(NetNom("lvl"), 0.0);
      double lp = GVGet(NetNom("last"), 0.0);
      if(lp > 0.0)
         s.oxirgiNarx = lp;
      double lt = GVGet(NetNom("time"), 0.0);
      if(lt > 0.0)
         s.oxirgiVaqt = (datetime)lt;
      double bl = GVGet(NetNom("base"), 0.0);
      if(bl > 0.0)
         s.bazaLot = bl;
     }
  }

//+------------------------------------------------------------------+
//| Eng yomon holat: savat + yangi pozitsiya + qolgan bosqichlar     |
//| hammasi qattiq SL da yopilsa yo'qotiladigan summa                |
//+------------------------------------------------------------------+
double EngYomonZarar(const int dir, const double sl, const double yangiLot, const double yangiNarx,
                     const int yangiDaraja, const double bazaLot)
  {
   double birlik = NarxBirlikQiymati(dir);
   if(birlik <= 0.0 || sl <= 0.0)
      return DBL_MAX;
   double kom = CommissionPerLot;
   double z   = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0 || (ulong)PositionGetInteger(POSITION_MAGIC) != g_magic)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      long typ = PositionGetInteger(POSITION_TYPE);
      if((dir > 0 && typ != POSITION_TYPE_BUY) || (dir < 0 && typ != POSITION_TYPE_SELL))
         continue;
      double vol = PositionGetDouble(POSITION_VOLUME);
      z += vol * (MathAbs(PositionGetDouble(POSITION_PRICE_OPEN) - sl) * birlik + kom);
     }
   z += yangiLot * (MathAbs(yangiNarx - sl) * birlik + kom);
   if(S.martin)
     {
      double grid = GridMasofa();
      double p    = yangiNarx;
      for(int d = yangiDaraja + 1; d <= S.maxSteps; d++)
        {
         p = (dir > 0) ? p - grid : p + grid;
         if((dir > 0 && p <= sl) || (dir < 0 && p >= sl))
            break;
         double l = LotNorm(bazaLot * MathPow(S.mult, d), true);
         z += l * (MathAbs(p - sl) * birlik + kom);
        }
     }
   return z;
  }

//--- Butun seriya SeriesRiskPercent ga teng bo'ladigan boshlang'ich lot
double SeriyaLot(const int dir, const double grid, const double extra)
  {
   double birlik = NarxBirlikQiymati(dir);
   if(birlik <= 0.0)
      return 0.0;
   int    steps = S.martin ? S.maxSteps : 0;
   double jami  = 0.0;
   for(int i = 0; i <= steps; i++)
     {
      double k    = MathPow(S.mult, i);
      double dist = (steps - i) * grid + extra;
      jami += k * (dist * birlik + CommissionPerLot);
     }
   if(jami <= 0.0)
      return 0.0;
   return AccountInfoDouble(ACCOUNT_BALANCE) * S.seriesRisk / 100.0 / jami;
  }

//+------------------------------------------------------------------+
//| Sessiya va vaqt                                                  |
//+------------------------------------------------------------------+
bool HaftaOxiriYopiq()
  {
   datetime f, e;
   return !SymbolInfoSessionTrade(_Symbol, SATURDAY, 0, f, e);
  }

bool SessiyaOchiq()
  {
   MqlDateTime t;
   TimeToStruct(TimeCurrent(), t);
   long     sek = (long)t.hour * 3600 + (long)t.min * 60 + (long)t.sec;
   datetime f, e;
   for(uint i = 0; SymbolInfoSessionTrade(_Symbol, (ENUM_DAY_OF_WEEK)t.day_of_week, i, f, e); i++)
     {
      long bosh = (long)f;
      long oxir = (long)e;
      if(sek >= bosh && sek < oxir)
         return (oxir >= 86400 || oxir - sek >= 1800);
     }
   return false;
  }

bool JumaYopishVaqti()
  {
   if(!HaftaOxiriYopiq())
      return false;
   MqlDateTime t;
   TimeToStruct(TimeCurrent(), t);
   if(t.day_of_week == 0 || t.day_of_week == 6)
      return true;
   return (t.day_of_week == 5 && t.hour >= CloseFridayHour);
  }

//+------------------------------------------------------------------+
//| Bitta juftlikda bitta nusxa (dublikatdan himoya)                 |
//+------------------------------------------------------------------+
bool NusxaEgasi()
  {
   if(AllowDuplicateInstances || MQLInfoInteger(MQL_TESTER))
      return true;
   string on    = GVNom("own_" + _Symbol);
   string hn    = GVNom("hb_" + _Symbol);
   double egasi = GVGet(on, 0.0);
   double hb    = GVGet(hn, 0.0);
   bool   eski  = ((double)TimeLocal() - hb > 90.0);
   if(egasi == 0.0 || egasi == g_token || eski)
     {
      GlobalVariableSet(on, g_token);
      GlobalVariableSet(hn, (double)TimeLocal());
      return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Pozitsiyani yopish                                               |
//+------------------------------------------------------------------+
bool Yopish(const ulong ticket, const string sabab)
  {
   for(int u = 1; u <= MaxRetries; u++)
     {
      if(!PositionSelectByTicket(ticket))
         return true;
      bool ok = g_trade.PositionClose(ticket, (ulong)MaxSlippagePoints);
      uint rc = g_trade.ResultRetcode();
      if(ok && (rc == TRADE_RETCODE_DONE || rc == TRADE_RETCODE_DONE_PARTIAL || rc == TRADE_RETCODE_PLACED))
        {
         PrintFormat("Pozitsiya #%I64u yopildi. Sabab: %s", ticket, sabab);
         return true;
        }
      PrintFormat("XATO: yopish #%I64u urinish %d/%d, retcode=%u (%s)", ticket, u, MaxRetries, rc, g_trade.ResultRetcodeDescription());
      if(!QaytaUrinish(rc))
         return false;
      Sleep(300);
     }
   return false;
  }

//--- Savatni to'liq yopish
bool SavatYop(const Savat &s, const string sabab)
  {
   bool hammasi = true;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0 || (ulong)PositionGetInteger(POSITION_MAGIC) != g_magic)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      long typ = PositionGetInteger(POSITION_TYPE);
      if((s.dir > 0 && typ != POSITION_TYPE_BUY) || (s.dir < 0 && typ != POSITION_TYPE_SELL))
         continue;
      if(!Yopish(t, sabab))
         hammasi = false;
     }
   if(s.sof >= 0.0)
      g_lastProfitClose = TimeCurrent();
   else
      g_lastLossClose = TimeCurrent();
   PrintFormat("Savat %s yopildi: %d pozitsiya, %.2f lot, natija %.2f. Sabab: %s",
               s.dir > 0 ? "BUY" : "SELL", s.soni, s.lotlar, s.sof, sabab);
   return hammasi;
  }

//--- Barcha juftliklardagi barcha KMU3 pozitsiyalarini yopish
void FavqulodaYopish(const string sabab)
  {
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0 || !BizningMagic((ulong)PositionGetInteger(POSITION_MAGIC)))
         continue;
      Yopish(t, "FAVQULODA: " + sabab);
      n++;
     }
   if(n > 0)
     {
      PrintFormat("FAVQULODA YOPISH (%s): %d pozitsiya", sabab, n);
      g_lastLossClose = TimeCurrent();
     }
  }

//+------------------------------------------------------------------+
//| Hisob bo'yicha risk (barcha nusxalar uchun umumiy)               |
//+------------------------------------------------------------------+
bool HisobRiski(string &sabab)
  {
   double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);

   double peak = GVGet(GVNom("peak"), 0.0);
   if(eq > peak)
     {
      peak = eq;
      GlobalVariableSet(GVNom("peak"), peak);
     }
   datetime kun = KunBoshi(TimeCurrent());
   if((datetime)GVGet(GVNom("day"), 0.0) != kun)
     {
      GlobalVariableSet(GVNom("day"), (double)kun);
      GlobalVariableSet(GVNom("dayeq"), MathMax(eq, bal));
     }
   double dayEq = GVGet(GVNom("dayeq"), eq);

   if(GVGet(GVNom("stop"), 0.0) > 0.0)
     {
      sabab = "TO'XTATILGAN: equity drawdown limiti. Tiklash: ResetLimits=true";
      return false;
     }
   if(GVGet(GVNom("stopday"), 0.0) == (double)kun)
     {
      sabab = "TO'XTATILGAN: kunlik zarar limiti, ertaga davom etadi";
      return false;
     }
   if(MaxEquityDrawdownPercent > 0.0 && peak > 0.0 && eq <= peak * (1.0 - MaxEquityDrawdownPercent / 100.0))
     {
      if(EmergencyCloseOnLimit)
         FavqulodaYopish("equity drawdown limiti");
      if(StopTradingAfterLossLimit)
         GlobalVariableSet(GVNom("stop"), 1.0);
      sabab = StringFormat("EQUITY DRAWDOWN LIMITI: %.2f -> %.2f (%.0f%%)", peak, eq, MaxEquityDrawdownPercent);
      return false;
     }
   if(MaxDailyLossPercent > 0.0 && dayEq > 0.0 && eq <= dayEq * (1.0 - MaxDailyLossPercent / 100.0))
     {
      if(EmergencyCloseOnLimit)
         FavqulodaYopish("kunlik zarar limiti");
      if(StopTradingAfterLossLimit)
         GlobalVariableSet(GVNom("stopday"), (double)kun);
      sabab = StringFormat("KUNLIK ZARAR LIMITI: %.2f -> %.2f (%.0f%%)", dayEq, eq, MaxDailyLossPercent);
      return false;
     }
   double marja = AccountInfoDouble(ACCOUNT_MARGIN);
   double ml    = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
   if(marja > 0.0 && EmergencyMarginLevel > 0.0 && ml < EmergencyMarginLevel)
     {
      FavqulodaYopish(StringFormat("margin level %.0f%%", ml));
      sabab = StringFormat("MARGIN LEVEL %.0f%% < %.0f%%", ml, EmergencyMarginLevel);
      return false;
     }
   if(marja > 0.0 && MinMarginLevel > 0.0 && ml < MinMarginLevel)
     {
      sabab = StringFormat("Margin level past: %.0f%% < %.0f%%", ml, MinMarginLevel);
      return false;
     }
   sabab = "";
   return true;
  }

//+------------------------------------------------------------------+
//| Juftlik bo'yicha ruxsat (vaqt, sessiya, spred)                   |
//+------------------------------------------------------------------+
bool BelgiRuxsat(string &kalit, string &sabab)
  {
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED))
     {
      kalit = "auto";
      sabab = "Avtosavdo o'chirilgan";
      return false;
     }
   if(SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE) != SYMBOL_TRADE_MODE_FULL)
     {
      kalit = "mode";
      sabab = "Juftlikda savdo cheklangan";
      return false;
     }
   if(!SessiyaOchiq())
     {
      kalit = "sess";
      sabab = "Juftlik sessiyasi yopiq yoki yopilishiga oz qoldi";
      return false;
     }
   MqlDateTime t;
   TimeToStruct(TimeCurrent(), t);
   if(HaftaOxiriYopiq() && t.day_of_week == 5 && t.hour >= CloseFridayHour - 1)
     {
      kalit = "fri";
      sabab = "Juma, savdo tugagan";
      return false;
     }
   if(t.hour < TradeStartHour || t.hour >= TradeEndHour)
     {
      kalit = "hour";
      sabab = StringFormat("Savdo vaqti emas (%02d:00-%02d:00)", TradeStartHour, TradeEndHour);
      return false;
     }
   if(SkipRollover)
     {
      bool r = (RolloverStartHour > RolloverEndHour)
               ? (t.hour >= RolloverStartHour || t.hour < RolloverEndHour)
               : (t.hour >= RolloverStartHour && t.hour < RolloverEndHour);
      if(r)
        {
         kalit = "roll";
         sabab = "Rollover oralig'i (spred keng)";
         return false;
        }
     }
   int sp = JoriySpred();
   if(MaxSpreadPoints > 0 && sp > MaxSpreadPoints)
     {
      kalit = "spr";
      sabab = StringFormat("Spred katta: %d > %d punkt", sp, MaxSpreadPoints);
      return false;
     }
   double tp = TPXom();
   if(tp > 0.0 && sp > tp * MaxSpreadTPPercent / 100.0)
     {
      kalit = "sprtp";
      sabab = StringFormat("Spred TP ga nisbatan katta: %d punkt, TP %.0f punkt (limit %.0f%%)", sp, tp, MaxSpreadTPPercent);
      return false;
     }
   kalit = "";
   sabab = "";
   return true;
  }

//--- Pozitsiya soni, lot va marja limitlari
bool LimitlarOK(const int dir, const double lot, string &sabab)
  {
   if(PozSoni(true) + 1 > S.maxPerSymbol)
     {
      sabab = StringFormat("Juftlikda pozitsiya limiti: %d", S.maxPerSymbol);
      return false;
     }
   if(PozSoni(false) + 1 > S.maxTotal)
     {
      sabab = StringFormat("Hisobda pozitsiya limiti: %d", S.maxTotal);
      return false;
     }
   if(MaxTotalExposure > 0.0 && JamiLot() + lot > MaxTotalExposure + 1e-9)
     {
      sabab = StringFormat("Jami lot limiti: %.2f + %.2f > %.2f", JamiLot(), lot, MaxTotalExposure);
      return false;
     }
   MqlTick t;
   if(!SymbolInfoTick(_Symbol, t))
     {
      sabab = "Narx yo'q";
      return false;
     }
   double marja = 0.0;
   if(!OrderCalcMargin(dir > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, _Symbol, lot, dir > 0 ? t.ask : t.bid, marja))
     {
      sabab = "Marjani hisoblab bo'lmadi";
      return false;
     }
   double bosh = AccountInfoDouble(ACCOUNT_MARGIN_FREE) - marja;
   if(bosh < AccountInfoDouble(ACCOUNT_EQUITY) * MinFreeMarginPercent / 100.0)
     {
      sabab = StringFormat("Bo'sh marja yetarli emas (kerak %.2f, bo'sh %.2f)", marja, AccountInfoDouble(ACCOUNT_MARGIN_FREE));
      return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
//| Pozitsiya ochish                                                 |
//+------------------------------------------------------------------+
bool Och(const int dir, const double lot, const double sl, const int daraja, const string tur, string &sabab)
  {
   string izoh = StringFormat("K3|L%d|%s", daraja, tur);
   for(int u = 1; u <= MaxRetries; u++)
     {
      MqlTick t;
      if(!SymbolInfoTick(_Symbol, t))
        {
         Sleep(200);
         continue;
        }
      double narx  = (dir > 0) ? t.ask : t.bid;
      double stops = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
      if(sl > 0.0 && ((dir > 0 && t.bid - sl <= stops) || (dir < 0 && sl - t.ask <= stops)))
        {
         sabab = "SL narxga juda yaqin (stops level)";
         return false;
        }
      bool ok = (dir > 0) ? g_trade.Buy(lot, _Symbol, narx, sl, 0.0, izoh)
                          : g_trade.Sell(lot, _Symbol, narx, sl, 0.0, izoh);
      uint rc = g_trade.ResultRetcode();
      if(ok && (rc == TRADE_RETCODE_DONE || rc == TRADE_RETCODE_DONE_PARTIAL || rc == TRADE_RETCODE_PLACED))
        {
         double fakt = g_trade.ResultPrice() > 0.0 ? g_trade.ResultPrice() : narx;
         PrintFormat("Ochildi [%s]: %s %.2f lot @ %s, daraja %d/%d, SL %s, rejim %s, spred %d",
                     tur, dir > 0 ? "BUY" : "SELL", lot, DoubleToString(fakt, _Digits), daraja, S.maxSteps,
                     DoubleToString(sl, _Digits), g_rejimNow == 1 ? "trend" : "range", JoriySpred());
         if(g_netting)
           {
            GlobalVariableSet(NetNom("lvl"), (double)daraja);
            GlobalVariableSet(NetNom("last"), fakt);
            GlobalVariableSet(NetNom("time"), (double)TimeCurrent());
            if(daraja == 0 && tur == "S")
               GlobalVariableSet(NetNom("base"), lot);
           }
         return true;
        }
      PrintFormat("XATO: ochish urinish %d/%d, retcode=%u (%s)", u, MaxRetries, rc, g_trade.ResultRetcodeDescription());
      if(!QaytaUrinish(rc))
        {
         sabab = "Ochish rad etildi: " + g_trade.ResultRetcodeDescription();
         return false;
        }
      Sleep(300);
     }
   sabab = "Ochish muvaffaqiyatsiz";
   return false;
  }

//+------------------------------------------------------------------+
//| Signal: trend - EMA pullback, range - Bollinger + RSI            |
//+------------------------------------------------------------------+
bool SignalHisobla(int &sig)
  {
   sig = 0;
   double ef[], es[], adx[], rsi[], bu[], bl[], atr[], a15[];
   if(!Bufer(g_hEmaF, 0, 1, 3, ef) || !Bufer(g_hEmaS, 0, 1, 1, es) || !Bufer(g_hAdx, 0, 1, 1, adx)
      || !Bufer(g_hRsi, 0, 1, 2, rsi) || !Bufer(g_hBB, 1, 1, 1, bu) || !Bufer(g_hBB, 2, 1, 1, bl)
      || !Bufer(g_hAtrS, 0, 1, 1, atr) || !Bufer(g_hAtr15, 0, 1, 1, a15))
      return false;
   MqlRates r[];
   ArraySetAsSeries(r, true);
   if(CopyRates(_Symbol, S.tf, 1, 1, r) < 1)
      return false;

   g_atrS     = atr[0];
   g_atr15    = a15[0];
   g_adx      = adx[0];
   g_trendDir = (ef[0] > es[0]) ? 1 : ((ef[0] < es[0]) ? -1 : 0);
   double a   = atr[0];
   if(a <= 0.0)
      return false;

   if(adx[0] >= S.adxTrend)
     {
      g_rejimNow = 1;
      if(!UseTrendSignals)
         return true;
      bool up = (ef[0] > es[0] && ef[0] > ef[2]);
      bool dn = (ef[0] < es[0] && ef[0] < ef[2]);
      // pullback: sham tez EMA ga yaqinlashdi va trend tomonga yopildi
      if(up && r[0].low <= ef[0] + S.pullbackATR * a && r[0].close > ef[0] && r[0].close > r[0].open)
         sig = 1;
      else
         if(dn && r[0].high >= ef[0] - S.pullbackATR * a && r[0].close < ef[0] && r[0].close < r[0].open)
            sig = -1;
      return true;
     }

   g_rejimNow = 0;
   if(!UseRangeSignals)
      return true;
   // range: chegaraga tegish + RSI haddan oshgan -> o'rtaga qaytishga kirish
   double rmin = MathMin(rsi[0], rsi[1]);
   double rmax = MathMax(rsi[0], rsi[1]);
   if(r[0].low <= bl[0] && rmin <= S.rsiBuy)
      sig = 1;
   else
      if(r[0].high >= bu[0] && rmax >= S.rsiSell)
         sig = -1;
   return true;
  }

void YangiBar()
  {
   datetime bar = iTime(_Symbol, S.tf, 0);
   if(bar == 0 || bar == g_bar)
      return;
   int sig = 0;
   if(!SignalHisobla(sig))
      return;   // ma'lumot tayyor emas: keyingi tickda qayta uriniladi
   g_bar        = bar;
   g_barSignal  = sig;
   g_entriesBar = 0;
  }

//+------------------------------------------------------------------+
//| Savatni boshqarish: TP, SL, vaqt                                 |
//+------------------------------------------------------------------+
void SavatBoshqar(const Savat &s)
  {
   if(s.soni == 0)
      return;
   datetime hozir   = TimeCurrent();
   double   bal     = AccountInfoDouble(ACCOUNT_BALANCE);
   double   tpPts   = TPPunkt();
   bool     savatmi = (s.soni > 1 || s.daraja > 0);
   double   baza    = (s.bazaLot > 0.0) ? s.bazaLot : s.lotlar / s.soni;
   double   maqsad;

   if(!savatmi)
      maqsad = (QuickTPMoney > 0.0) ? QuickTPMoney : PulQiymat(s.lotlar, tpPts);
   else
      maqsad = (BasketTakeProfitMoney > 0.0) ? BasketTakeProfitMoney : PulQiymat(baza, tpPts) * S.basketTPKoef;
   maqsad = MathMax(maqsad, MinNetProfitMoney);
   maqsad = MathMax(maqsad, 0.01);
   if(s.dir > 0)
      g_tpMaqsadB = maqsad;
   else
      g_tpMaqsadS = maqsad;

   // --- zarar bilan yopish shartlari (MinHold ga bog'liq emas)
   if(BasketStopLossMoney > 0.0 && s.sof <= -BasketStopLossMoney)
     {
      SavatYop(s, StringFormat("Basket SL: %.2f", s.sof));
      return;
     }
   if(MaxBasketDrawdownPercent > 0.0 && s.sof <= -bal * MaxBasketDrawdownPercent / 100.0)
     {
      SavatYop(s, StringFormat("Savat zarari %.2f >= balansning %.0f%%", s.sof, MaxBasketDrawdownPercent));
      return;
     }
   if(JumaYopishVaqti())
     {
      SavatYop(s, "Juma yopilishi");
      return;
     }
   if(MaxHoldHours > 0 && hozir - s.birinchiVaqt >= MaxHoldHours * 3600)
     {
      SavatYop(s, StringFormat("Vaqt chegarasi: %d soat", MaxHoldHours));
      return;
     }

   // --- foyda bilan yopish
   if(hozir - s.oxirgiVaqt < MinHoldSeconds)
      return;
   if(savatmi && !EnableBasketProfitClose && !g_netting)
     {
      // har bir pozitsiya o'z TP siga yetganda alohida yopiladi
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong t = PositionGetTicket(i);
         if(t == 0 || (ulong)PositionGetInteger(POSITION_MAGIC) != g_magic)
            continue;
         if(PositionGetString(POSITION_SYMBOL) != _Symbol)
            continue;
         long typ = PositionGetInteger(POSITION_TYPE);
         if((s.dir > 0 && typ != POSITION_TYPE_BUY) || (s.dir < 0 && typ != POSITION_TYPE_SELL))
            continue;
         double vol = PositionGetDouble(POSITION_VOLUME);
         double pr  = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
         pr += Komissiya((ulong)PositionGetInteger(POSITION_IDENTIFIER), vol);
         double m = MathMax(PulQiymat(vol, tpPts), MathMax(MinNetProfitMoney, 0.01));
         if(pr >= m && Yopish(t, StringFormat("Pozitsiya TP: sof %.2f", pr)))
            g_lastProfitClose = hozir;
        }
      return;
     }
   if(s.sof >= maqsad)
      SavatYop(s, StringFormat("%s TP: sof %.2f >= %.2f", savatmi ? "Basket" : "Quick", s.sof, maqsad));
  }

//+------------------------------------------------------------------+
//| Martingeyl bosqichi                                              |
//+------------------------------------------------------------------+
bool MartingeylQadam(const Savat &s, string &sabab)
  {
   if(!S.martin || s.soni == 0 || s.daraja >= S.maxSteps)
      return false;
   MqlTick t;
   if(!SymbolInfoTick(_Symbol, t))
      return false;
   double narx   = (s.dir > 0) ? t.ask : t.bid;
   double grid   = GridMasofa();
   double qarshi = (s.dir > 0) ? s.oxirgiNarx - narx : narx - s.oxirgiNarx;
   if(qarshi < grid)
      return false;   // shart 1: narx setka masofasiga yetmagan

   string yon = (s.dir > 0) ? "BUY" : "SELL";
   if(TimeCurrent() - s.oxirgiVaqt < S.minStepSec)
     {
      sabab = StringFormat("%s bosqich %d: minimal vaqt kutilmoqda", yon, s.daraja + 1);
      return false;
     }
   if(RequireNewBarForStep && iBarShift(_Symbol, S.tf, s.oxirgiVaqt, false) < 1)
     {
      sabab = StringFormat("%s bosqich %d: yangi sham kutilmoqda", yon, s.daraja + 1);
      return false;
     }
   if(BlockStepAgainstStrongTrend && g_adx >= AdxStrongLevel && g_trendDir == -s.dir)
     {
      sabab = StringFormat("%s bosqich %d: kuchli qarshi trend (ADX %.0f)", yon, s.daraja + 1, g_adx);
      return false;
     }
   double baza = (s.bazaLot > 0.0) ? s.bazaLot : LotNorm(s.lotlar / s.soni, false);
   double lot  = LotNorm(baza * MathPow(S.mult, s.daraja + 1), true);
   if(lot <= 0.0)
     {
      sabab = "Bosqich lotini hisoblab bo'lmadi";
      return false;
     }
   if(MaxBasketLots > 0.0 && s.lotlar + lot > MaxBasketLots + 1e-9)
     {
      sabab = StringFormat("%s bosqich: savat lot limiti %.2f", yon, MaxBasketLots);
      return false;
     }
   if(!LimitlarOK(s.dir, lot, sabab))
      return false;
   double sl = (s.sl > 0.0) ? s.sl : NormNarx(s.dir > 0 ? s.birinchiNarx - QattiqSLMasofa() : s.birinchiNarx + QattiqSLMasofa());
   if(MaxBasketDrawdownPercent > 0.0)
     {
      double z   = EngYomonZarar(s.dir, sl, lot, narx, s.daraja + 1, baza);
      double lim = AccountInfoDouble(ACCOUNT_BALANCE) * MaxBasketDrawdownPercent / 100.0;
      if(z > lim)
        {
         sabab = StringFormat("%s bosqich: eng yomon holat zarari %.2f > limit %.2f", yon, z, lim);
         return false;
        }
     }
   return Och(s.dir, lot, sl, s.daraja + 1, "M", sabab);
  }

//+------------------------------------------------------------------+
//| Yangi kirish (boshlang'ich yoki add-on)                          |
//+------------------------------------------------------------------+
bool BoshlangichOch(const int dir, string &sabab)
  {
   MqlTick t;
   if(!SymbolInfoTick(_Symbol, t))
      return false;
   double narx  = (dir > 0) ? t.ask : t.bid;
   double grid  = GridMasofa();
   double extra = g_atr15 * HardSLExtraATR;
   double stops = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   double m     = MathMax(QattiqSLMasofa(), stops + (t.ask - t.bid) + 10 * _Point);
   double sl    = NormNarx(dir > 0 ? narx - m : narx + m);

   double lot;
   if(LotMode == LOT_SERIES_RISK)
     {
      double xom = SeriyaLot(dir, grid, extra);
      lot = LotNorm(xom, false);
      if(lot <= 0.0)
        {
         sabab = StringFormat("Minimal lot ham seriya xavfidan katta (hisoblangan %.4f lot). Bu juftlik shu balans uchun juda xavfli.", xom);
         return false;
        }
     }
   else
     {
      lot = LotNorm(InitialLot, false);
      if(lot <= 0.0)
        {
         sabab = "InitialLot juftlikning minimal lotidan kichik";
         return false;
        }
     }
   if(!LimitlarOK(dir, lot, sabab))
      return false;
   double z   = EngYomonZarar(dir, sl, lot, narx, 0, lot);
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   if(MaxBasketDrawdownPercent > 0.0 && z > bal * MaxBasketDrawdownPercent / 100.0)
     {
      sabab = StringFormat("Eng yomon seriya zarari %.2f (%.1f%%) > limit %.0f%%", z, z / bal * 100.0, MaxBasketDrawdownPercent);
      return false;
     }
   if(Och(dir, lot, sl, 0, "S", sabab))
     {
      PrintFormat("Seriya: baza lot %.2f, setka %.0f punkt, qattiq SL %.0f punkt, eng yomon zarar %.2f (%.1f%% balans)",
                  lot, grid / _Point, m / _Point, z, z / bal * 100.0);
      return true;
     }
   return false;
  }

bool YangiKirish(const Savat &b, const Savat &s, string &kalit, string &sabab)
  {
   if(g_atrS <= 0.0 || g_atr15 <= 0.0)
     {
      kalit = "data";
      sabab = "Indikator ma'lumoti tayyor emas";
      return false;
     }
   int sig = g_barSignal;
   if(sig == 0)
     {
      kalit = "nosig";
      sabab = StringFormat("Signal kutilmoqda (%s, ADX %.1f)", g_rejimNow == 1 ? "trend" : "range", g_adx);
      return false;
     }
   datetime hozir = TimeCurrent();
   if(EntryWindowSeconds > 0 && hozir - g_bar > EntryWindowSeconds)
     {
      kalit = "win";
      sabab = "Signal oynasi o'tdi, keyingi sham kutilmoqda";
      return false;
     }
   int maxBar = EnableReEntry ? S.maxEntriesPerBar : 1;
   if(g_entriesBar >= maxBar)
     {
      kalit = "used";
      sabab = "Bu shamning signali ishlatildi";
      return false;
     }
   if(g_lastLossClose > 0 && hozir - g_lastLossClose < LossCooldownMinutes * 60)
     {
      kalit = "losscd";
      sabab = StringFormat("Zarardan keyin kutish: %d daqiqa", LossCooldownMinutes);
      return false;
     }
   if(g_lastProfitClose > 0)
     {
      if(!AllowNewEntryAfterProfitClose && iBarShift(_Symbol, S.tf, g_lastProfitClose, false) == 0)
        {
         kalit = "profcd";
         sabab = "Foyda bilan yopildi, yangi sham kutilmoqda";
         return false;
        }
      if(hozir - g_lastProfitClose < S.reEntryCooldown)
        {
         kalit = "profcd";
         sabab = StringFormat("Foydadan keyin kutish: %d soniya", S.reEntryCooldown);
         return false;
        }
     }

   Savat bir, qarshi;
   if(sig > 0)
     {
      bir    = b;
      qarshi = s;
     }
   else
     {
      bir    = s;
      qarshi = b;
     }
   if(qarshi.soni > 0 && (g_netting || !AllowHedgeBaskets))
     {
      kalit = "opp";
      sabab = "Qarama-qarshi savat ochiq";
      return false;
     }

   bool ok;
   if(bir.soni == 0)
      ok = BoshlangichOch(sig, sabab);
   else
     {
      // add-on: savat foydada va narx foyda tomonga yetarli siljigan
      if(!S.multiple || g_netting)
        {
         kalit = "basket";
         sabab = "Shu yo'nalishda savat ochiq";
         return false;
        }
      if(bir.sof < 0.0)
        {
         kalit = "addloss";
         sabab = "Savat zararda, add-on ochilmaydi";
         return false;
        }
      MqlTick t;
      if(!SymbolInfoTick(_Symbol, t))
         return false;
      double narx = (sig > 0) ? t.ask : t.bid;
      double fav  = (sig > 0) ? narx - bir.oxirgiNarx : bir.oxirgiNarx - narx;
      if(fav < AddOnMinDistanceATR * g_atrS)
        {
         kalit = "adddist";
         sabab = "Add-on: foyda tomonga masofa yetarli emas";
         return false;
        }
      double baza = (bir.bazaLot > 0.0) ? bir.bazaLot : LotNorm(bir.lotlar / bir.soni, false);
      double lot  = LotNorm(baza, false);
      if(lot <= 0.0)
        {
         kalit = "lim";
         sabab = "Add-on lotini hisoblab bo'lmadi";
         return false;
        }
      if(!LimitlarOK(sig, lot, sabab))
        {
         kalit = "lim";
         return false;
        }
      if(MaxBasketDrawdownPercent > 0.0)
        {
         double z   = EngYomonZarar(sig, bir.sl, lot, narx, bir.daraja, baza);
         double lim = AccountInfoDouble(ACCOUNT_BALANCE) * MaxBasketDrawdownPercent / 100.0;
         if(z > lim)
           {
            kalit = "addrisk";
            sabab = StringFormat("Add-on: eng yomon holat zarari %.2f > limit %.2f", z, lim);
            return false;
           }
        }
      ok = Och(sig, lot, bir.sl, bir.daraja, "A", sabab);
     }
   if(ok)
     {
      g_entriesBar++;
      kalit = "";
      sabab = "Savdo ochildi";
     }
   else
      if(kalit == "")
         kalit = "fail";
   return ok;
  }

//+------------------------------------------------------------------+
//| Grafik paneli                                                    |
//+------------------------------------------------------------------+
void Panel(const Savat &b, const Savat &s)
  {
   if(!ShowPanel)
      return;
   if(MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE))
      return;
   string val  = AccountInfoString(ACCOUNT_CURRENCY);
   double eq   = AccountInfoDouble(ACCOUNT_EQUITY);
   double peak = GVGet(GVNom("peak"), eq);
   double dd   = (peak > 0.0) ? (peak - eq) / peak * 100.0 : 0.0;
   string m = StringFormat("=== KvantMartinUz v3 [%s] === %s  signal TF %s\n", RejimNomi(), _Symbol, EnumToString(S.tf));
   m += StringFormat("Equity: %.2f %s   Tushish: %.1f%% / %.0f%%\n", eq, val, dd, MaxEquityDrawdownPercent);
   m += StringFormat("Bozor: %s  ADX %.1f  Signal: %s\n", g_rejimNow == 1 ? "trend" : "range", g_adx,
                     g_barSignal > 0 ? "BUY" : (g_barSignal < 0 ? "SELL" : "yo'q"));
   m += StringFormat("TP: %.0f punkt  Setka: %.0f punkt  Spred: %d\n", TPPunkt(), GridMasofa() / _Point, JoriySpred());
   m += StringFormat("BUY savat: %d poz, %.2f lot, daraja %d/%d, sof %.2f (maqsad %.2f)\n",
                     b.soni, b.lotlar, b.daraja, S.maxSteps, b.sof, g_tpMaqsadB);
   m += StringFormat("SELL savat: %d poz, %.2f lot, daraja %d/%d, sof %.2f (maqsad %.2f)\n",
                     s.soni, s.lotlar, s.daraja, S.maxSteps, s.sof, g_tpMaqsadS);
   m += StringFormat("Pozitsiyalar: juftlik %d/%d, hisob %d/%d\n", PozSoni(true), S.maxPerSymbol, PozSoni(false), S.maxTotal);
   m += "Holat: " + g_holat;
   Comment(m);
  }

//+------------------------------------------------------------------+
//| Tester statistikasi                                              |
//+------------------------------------------------------------------+
void StatYangila()
  {
   int n = PozSoni(false);
   if(n > g_maxSimul)
      g_maxSimul = n;
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(eq > 0.0)
     {
      double u = AccountInfoDouble(ACCOUNT_MARGIN) / eq * 100.0;
      if(u > g_maxMarginUse)
         g_maxMarginUse = u;
     }
  }

//+------------------------------------------------------------------+
//| Ishga tushirish                                                  |
//+------------------------------------------------------------------+
int OnInit()
  {
   RejimniQollash();

   if(MagicOffset < 0 || MagicOffset > 999 || S.maxSteps < 0 || S.maxSteps > 9 || S.mult < 1.0 || S.mult > 3.0
      || S.maxPerSymbol < 1 || S.maxTotal < 1 || EmaFast >= EmaSlow || MaxRetries < 1 || MaxRetries > 5
      || TradeStartHour < 0 || TradeEndHour > 24 || TradeStartHour >= TradeEndHour || S.tpATR <= 0.0
      || (LotMode == LOT_SERIES_RISK && (S.seriesRisk <= 0.0 || S.seriesRisk > 50.0))
      || (LotMode == LOT_FIXED && InitialLot <= 0.0) || HardSLExtraATR <= 0.0)
     {
      Print("XATO: parametrlar noto'g'ri");
      return INIT_PARAMETERS_INCORRECT;
     }

   g_magic   = MagicBase + (ulong)MagicOffset;
   g_netting = ((ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING);
   if(g_netting && S.multiple)
     {
      Print("Netting hisob: add-on va qarama-qarshi savatlar o'chirildi (bitta pozitsiya).");
      S.multiple = false;
     }
   MathSrand((uint)(GetTickCount() ^ (uint)ChartID()));
   g_token = (double)(MathRand() * 32768 + MathRand() + 1);

   g_trade.SetExpertMagicNumber(g_magic);
   g_trade.SetDeviationInPoints((ulong)MaxSlippagePoints);
   g_trade.SetMarginMode();
   g_trade.LogLevel(LOG_LEVEL_ERRORS);
   if(!g_trade.SetTypeFillingBySymbol(_Symbol))
      Print("DIQQAT: to'ldirish turini aniqlab bo'lmadi, standart qiymat ishlatiladi");

   g_hEmaF  = iMA(_Symbol, S.tf, EmaFast, 0, MODE_EMA, PRICE_CLOSE);
   g_hEmaS  = iMA(_Symbol, S.tf, EmaSlow, 0, MODE_EMA, PRICE_CLOSE);
   g_hAdx   = iADX(_Symbol, S.tf, AdxPeriod);
   g_hRsi   = iRSI(_Symbol, S.tf, RsiPeriod, PRICE_CLOSE);
   g_hBB    = iBands(_Symbol, S.tf, BBPeriod, 0, BBDeviation, PRICE_CLOSE);
   g_hAtrS  = iATR(_Symbol, S.tf, ATR_DAVR);
   g_hAtr15 = iATR(_Symbol, PERIOD_M15, ATR_DAVR);
   if(g_hEmaF == INVALID_HANDLE || g_hEmaS == INVALID_HANDLE || g_hAdx == INVALID_HANDLE || g_hRsi == INVALID_HANDLE
      || g_hBB == INVALID_HANDLE || g_hAtrS == INVALID_HANDLE || g_hAtr15 == INVALID_HANDLE)
     {
      Print("XATO: indikatorlarni yaratib bo'lmadi");
      return INIT_FAILED;
     }

   if(MQLInfoInteger(MQL_TESTER))
      GlobalVariablesDeleteAll(KMU_PREFIX);
   if(ResetLimits)
     {
      GlobalVariableDel(GVNom("stop"));
      GlobalVariableDel(GVNom("stopday"));
      GlobalVariableDel(GVNom("peak"));
      Print("Limitlar tiklandi (ResetLimits=true). Keyin uni yana false qiling.");
     }

   EventSetTimer(10);
   PrintFormat("Ishga tushdi v3 [%s]: %s, signal %s, magic %I64u, %s, martingeyl %s (x%.2f, %d bosqich), seriya xavfi %.1f%%, pozitsiya %d/%d",
               RejimNomi(), _Symbol, EnumToString(S.tf), g_magic, g_netting ? "NETTING" : "HEDGING",
               S.martin ? "ha" : "yo'q", S.mult, S.maxSteps, S.seriesRisk, S.maxPerSymbol, S.maxTotal);
   return INIT_SUCCEEDED;
  }

void IndikatorBoshat(int &h)
  {
   if(h != INVALID_HANDLE)
      IndicatorRelease(h);
   h = INVALID_HANDLE;
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   IndikatorBoshat(g_hEmaF);
   IndikatorBoshat(g_hEmaS);
   IndikatorBoshat(g_hAdx);
   IndikatorBoshat(g_hRsi);
   IndikatorBoshat(g_hBB);
   IndikatorBoshat(g_hAtrS);
   IndikatorBoshat(g_hAtr15);
   if(!MQLInfoInteger(MQL_TESTER) && GVGet(GVNom("own_" + _Symbol), 0.0) == g_token)
     {
      GlobalVariableDel(GVNom("own_" + _Symbol));
      GlobalVariableDel(GVNom("hb_" + _Symbol));
     }
   if(MQLInfoInteger(MQL_TESTER))
     {
      int      kirish = 0;
      datetime bosh   = 0, oxir = 0;
      if(HistorySelect(0, TimeCurrent()))
        {
         int n = HistoryDealsTotal();
         for(int i = 0; i < n; i++)
           {
            ulong d = HistoryDealGetTicket(i);
            if(d == 0 || (ulong)HistoryDealGetInteger(d, DEAL_MAGIC) != g_magic)
               continue;
            if(HistoryDealGetInteger(d, DEAL_ENTRY) != DEAL_ENTRY_IN)
               continue;
            datetime dt = (datetime)HistoryDealGetInteger(d, DEAL_TIME);
            if(bosh == 0)
               bosh = dt;
            oxir = dt;
            kirish++;
           }
        }
      double kunlar = (oxir > bosh) ? (double)(oxir - bosh) / 86400.0 : 1.0;
      PrintFormat("STAT: kirishlar %d, kuniga %.2f, bir vaqtda eng ko'p pozitsiya %d, eng yuqori marja ishlatilishi %.1f%%",
                  kirish, kirish / kunlar, g_maxSimul, g_maxMarginUse);
     }
   Comment("");
   PrintFormat("To'xtatildi, sabab kodi %d", reason);
  }

void OnTimer()
  {
   if(!AllowDuplicateInstances && !MQLInfoInteger(MQL_TESTER) && GVGet(GVNom("own_" + _Symbol), 0.0) == g_token)
      GlobalVariableSet(GVNom("hb_" + _Symbol), (double)TimeLocal());
  }

//+------------------------------------------------------------------+
//| Har bir tick                                                     |
//+------------------------------------------------------------------+
void OnTick()
  {
   StatYangila();
   YangiBar();

   string kalit = "", sabab = "";
   bool   riskOK = HisobRiski(sabab);
   if(!riskOK)
      kalit = "risk";

   Savat b, s;
   SavatYig(1, b);
   SavatYig(-1, s);
   if(g_netting && b.soni == 0 && s.soni == 0 && GlobalVariableCheck(NetNom("lvl")))
     {
      GlobalVariableDel(NetNom("lvl"));
      GlobalVariableDel(NetNom("last"));
      GlobalVariableDel(NetNom("time"));
      GlobalVariableDel(NetNom("base"));
     }

   if(b.soni > 0)
      SavatBoshqar(b);
   if(s.soni > 0)
      SavatBoshqar(s);
   SavatYig(1, b);
   SavatYig(-1, s);

   if(riskOK && BelgiRuxsat(kalit, sabab))
     {
      string qs = "";
      bool   ochildi = false;
      if(MartingeylQadam(b, qs))
         ochildi = true;
      else
         if(MartingeylQadam(s, qs))
            ochildi = true;
      if(ochildi)
        {
         SavatYig(1, b);
         SavatYig(-1, s);
        }
      if(!NusxaEgasi())
        {
         kalit = "dup";
         sabab = "Bu juftlikda boshqa nusxa ishlayapti - bu nusxa yangi savdo ochmaydi";
        }
      else
        {
         YangiKirish(b, s, kalit, sabab);
         if(qs != "" && (kalit == "nosig" || kalit == "used"))
           {
            kalit = "step";
            sabab = qs;
           }
        }
     }
   Sabab(kalit, sabab);
   Panel(b, s);
  }

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;
   if(!HistoryDealSelect(trans.deal))
      return;
   if((ulong)HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != g_magic)
      return;
   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol)
      return;
   long e = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(e != DEAL_ENTRY_OUT && e != DEAL_ENTRY_OUT_BY && e != DEAL_ENTRY_INOUT)
      return;
   if(HistoryDealGetInteger(trans.deal, DEAL_REASON) == DEAL_REASON_SL)
     {
      g_lastLossClose = TimeCurrent();
      double p = HistoryDealGetDouble(trans.deal, DEAL_PROFIT) + HistoryDealGetDouble(trans.deal, DEAL_SWAP)
                 + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
      PrintFormat("Qattiq SL ishladi: deal #%I64u, natija %.2f", trans.deal, p);
     }
  }

//--- Optimallashtirish mezoni: foyda / maksimal equity drawdown (kamida 50 savdo)
double OnTester()
  {
   double savdo = TesterStatistics(STAT_TRADES);
   if(savdo < 50.0)
      return 0.0;
   double foyda = TesterStatistics(STAT_PROFIT);
   double dd    = TesterStatistics(STAT_EQUITY_DDREL_PERCENT);
   return foyda / MathMax(dd, 1.0);
  }
//+------------------------------------------------------------------+
