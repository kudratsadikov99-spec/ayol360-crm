//+------------------------------------------------------------------+
//|                                   KvantMartinUz2_70_Teskari.mq5 |
//|   v2: 24/7 va KO'P JUFTLIK. CHEKLANGAN martingeyl. YUQORI XAVF!  |
//|   - Har juftlik o'z siklini yuritadi (tarix juftlik bo'yicha).   |
//|   - Juftlikda bir vaqtda 1 pozitsiya, hisobda MaxOchiqPozitsiya. |
//|   - Savdo juftlik sessiyasi ochiq bo'lganda (kripto: dam olish   |
//|     kunlari ham). Spred filtri SL masofasiga nisbatan foizda.    |
//|   - Har bir pozitsiyada qattiq server SL.                        |
//|   - Zarardan keyin keyingi savdo xavfi x2, eng ko'pi MaxQadam.   |
//|   - MaxQadam zarar ketma-ket kelsa: sikl yopiladi, zarar qabul   |
//|     qilinadi (taxminan BazaRiskFoiz x (2^MaxQadam - 1) %),       |
//|     PauzaSoat pauza, keyin baza lotdan qayta boshlanadi.         |
//|   - Setka / o'rtachalash YO'Q: bir nechta pozitsiya ochilmaydi.  |
//+------------------------------------------------------------------+
#property copyright   "KvantMartinUz"
#property version     "2.00"
#property description "v2 TESKARI signal: pauzasiz, 24 soat, limit 70%. Faqat test uchun."

#include <Trade\Trade.mqh>

#define SIGNAL_TF   PERIOD_M15
#define TREND_TF    PERIOD_H1
#define TREND_EMA   50
#define ATR_DAVR    14

//+------------------------------------------------------------------+
//| Kirish parametrlari                                              |
//+------------------------------------------------------------------+
input group "=== Martingeyl (YUQORI XAVF) ==="
input double BazaRiskFoiz          = 0.8;   // Sikl birinchi savdosi xavfi, balansning %
input int    MaxQadam              = 5;     // Sikldagi eng ko'p savdo (xavf: 1,2,4,8,16 x baza)
input double TPKoef                = 1.0;   // Sikl foydasi = baza xavf x shu koeffitsient
input int    PauzaSoat             = 0;    // Sikl muvaffaqiyatsiz tugagach pauza, soat
input double UmumiyZararFoiz       = 70.0;  // Eng yuqori balansdan shuncha % tushsa - savdo to'liq to'xtaydi
input bool   UmumiyLimitniTiklash  = false; // true: eng yuqori balans hisobini qaytadan boshlash
input double KomissiyaUSDLot       = 0.0;   // Komissiya bahosi: 1 lot, ikki tomon, USD
input double ValyutaKoeffitsienti  = 0.0;   // Hisob valyutasi / USD (0 = avtomatik, Cent = 100)

input group "=== Signal va SL ==="
input bool   TeskariSignal         = true;  // true: signal teskari (BUY o'rniga SELL, SELL o'rniga BUY)
input double SLATRKoef             = 1.5;   // SL masofasi = ATR(M15) x shu koeffitsient
input int    MinSLPunkt            = 0;     // Minimal SL masofasi, punkt (0 = faqat spred bo'yicha)
input double MinSLSpredKoef        = 6.0;   // SL kamida spred x shu koeffitsient
input int    SavdoBoshSoat         = 0;     // Yangi savdo boshlanishi, server soati (0-24 = 24 soat)
input int    SavdoOxirSoat         = 24;    // Yangi savdo tugashi, server soati
input bool   RolloverniOtkazish    = false;  // Rollover oralig'ida (spred juda keng) savdo ochmaslik
input int    RolloverBoshSoat      = 23;    // Rollover boshlanishi, server soati
input int    RolloverOxirSoat      = 1;     // Rollover tugashi, server soati
input int    KirishOynasiSoniya    = 120;   // Yangi M15 sham ochilgach kirish oynasi, soniya
input int    MaxUshlabSoat         = 24;    // Pozitsiyani eng uzog'i bilan ushlab turish, soat

input group "=== Himoya ==="
input int    MaxOchiqPozitsiya     = 3;     // Butun hisobda bir vaqtda eng ko'p pozitsiya (barcha juftliklar)
input int    CooldownBars          = 1;     // Yopilgandan keyin kutish, M15 sham
input double MaxSpreadSLFoiz       = 15.0;  // Spred SL masofasining shu % idan oshsa savdo yo'q
input int    MaxSpreadPoints       = 0;     // Qo'shimcha: maksimal spred, punkt (0 = o'chiq)
input int    CloseFridayHour       = 20;    // Juma: shu soatda yopiladi (faqat dam olishda yopiladigan bozorlar)
input int    MinHoldSeconds        = 120;   // Minimal ushlab turish, soniya (SL bundan mustasno)
input int    TarixKunlar           = 30;    // Tarixdan tiklash chuqurligi, kun

input group "=== Texnik ==="
input ulong  MagicNumber           = 20261015; // Magic raqam
input int    MaxSlippagePunkt      = 10;    // Ruxsat etilgan sirpanish, punkt
input int    MaxUrinishlar         = 3;     // Xatoda urinishlar soni (1-3)
input bool   GrafikdaKorsatish     = true;  // Holatni grafikda ko'rsatish

//+------------------------------------------------------------------+
//| Global o'zgaruvchilar                                            |
//+------------------------------------------------------------------+
CTrade   g_savdo;
double   g_koef            = 1.0;
int      g_hEma            = INVALID_HANDLE;
int      g_hAtr            = INVALID_HANDLE;

double   g_choqqi          = 0.0;
int      g_qadam           = 0;       // joriy sikldagi zararlar soni
double   g_siklZarar       = 0.0;     // joriy siklda qoplanishi kerak bo'lgan zarar
int      g_muvaffaqiyatsiz = 0;       // tarix oynasidagi muvaffaqiyatsiz sikllar
int      g_kunSavdo        = 0;
double   g_kunNatija       = 0.0;
datetime g_pauzaGacha      = 0;
datetime g_oxirgiYopilish  = 0;
datetime g_kunBoshi        = 0;
datetime g_oxirgiTiklash   = 0;
bool     g_tarixYangila    = true;

datetime g_signalBar       = 0;
int      g_barSignal       = 0;
double   g_barSLMasofa     = 0.0;
bool     g_barIshlatildi   = false;

ulong    g_komPozId        = 0;
double   g_komQiymat       = 0.0;
bool     g_komAniq         = false;
ulong    g_tpPozId         = 0;
double   g_tpMaqsad        = 0.0;
bool     g_oldingiPozBor   = false;
double   g_ochiqSof        = 0.0;
string   g_holatMatn       = "";

//+------------------------------------------------------------------+
//| Yordamchi funksiyalar                                            |
//+------------------------------------------------------------------+
double USD(const double pul) { return (g_koef > 0.0) ? pul / g_koef : pul; }

datetime KunBoshi(const datetime t)
  {
   return (datetime)((long)t - (long)t % 86400);
  }

bool KoeffitsientAniqla()
  {
   if(ValyutaKoeffitsienti > 0.0)
     {
      g_koef = ValyutaKoeffitsienti;
      return true;
     }
   string v = AccountInfoString(ACCOUNT_CURRENCY);
   StringToUpper(v);
   if(v == "USD")
     {
      g_koef = 1.0;
      return true;
     }
   if(v == "USC" || v == "USX" || v == "USCENT" || v == "USDCENT" || StringFind(v, "CENT") >= 0)
     {
      g_koef = 100.0;
      return true;
     }
   PrintFormat("XATO: hisob valyutasi '%s' noma'lum. ValyutaKoeffitsienti ni qo'lda kiriting.", v);
   return false;
  }

//--- Sikl boshidagi balans asosida baza xavf
double BazaRisk()
  {
   return (AccountInfoDouble(ACCOUNT_BALANCE) + g_siklZarar) * BazaRiskFoiz / 100.0;
  }

//--- Joriy qadam xavfi: baza x 2^qadam
double QadamRisk()
  {
   return BazaRisk() * MathPow(2.0, g_qadam);
  }

//--- Sikl to'liq muvaffaqiyatsiz bo'lsa yo'qotiladigan foiz
double MaxSiklFoiz()
  {
   return BazaRiskFoiz * (MathPow(2.0, MaxQadam) - 1.0);
  }

string ChoqqiNomi()
  {
   return StringFormat("KMU_%I64u_choqqi", MagicNumber);
  }

void ChoqqiYangila()
  {
   double b = AccountInfoDouble(ACCOUNT_BALANCE);
   if(b > g_choqqi)
     {
      g_choqqi = b;
      GlobalVariableSet(ChoqqiNomi(), b);
     }
  }

bool UmumiyLimitYetdi()
  {
   return (g_choqqi > 0.0 && AccountInfoDouble(ACCOUNT_BALANCE) <= g_choqqi * (1.0 - UmumiyZararFoiz / 100.0));
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

int JoriySpred()
  {
   MqlTick t;
   if(!SymbolInfoTick(_Symbol, t))
      return INT_MAX;
   return (int)MathRound((t.ask - t.bid) / _Point);
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

bool Bufer(const int h, const int buf, const int bosh, const int soni, double &arr[])
  {
   ArraySetAsSeries(arr, true);
   return (CopyBuffer(h, buf, bosh, soni, arr) == soni);
  }

//+------------------------------------------------------------------+
//| Shu juftlikdagi o'z pozitsiyamiz (magic + juftlik)               |
//+------------------------------------------------------------------+
ulong OzPozitsiya(string &belgi)
  {
   ulong topildi = 0;
   int   soni    = 0;
   belgi = "";
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0)
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      soni++;
      if(topildi == 0)
        {
         topildi = t;
         belgi   = _Symbol;
        }
     }
   if(soni > 1)
      PrintFormat("DIQQAT: %s da magic %I64u bilan %d ta pozitsiya topildi! Bitta juftlikka faqat bitta EA qo'ying.",
                  _Symbol, MagicNumber, soni);
   if(topildi != 0)
      PositionSelectByTicket(topildi);
   return topildi;
  }

//--- Butun hisobdagi shu magic bilan ochiq pozitsiyalar soni (barcha juftliklar)
int JamiOchiq()
  {
   int soni = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t != 0 && (ulong)PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         soni++;
     }
   return soni;
  }

//--- Juftlik dam olish kunlari yopiladimi (shanba sessiyasi yo'q bo'lsa - ha)
bool HaftaOxiriYopiq()
  {
   datetime f, e;
   return !SymbolInfoSessionTrade(_Symbol, SATURDAY, 0, f, e);
  }

//--- Juftlikning savdo sessiyasi hozir ochiqmi (yopilishiga 30 daqiqadan kam qolgan bo'lsa - yo'q)
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

int Indeks(const ulong &arr[], const int soni, const ulong qiymat)
  {
   for(int i = 0; i < soni; i++)
      if(arr[i] == qiymat)
         return i;
   return -1;
  }

//+------------------------------------------------------------------+
//| Sikl holati (qadam, qoplanadigan zarar, pauza) tarixdan          |
//| tiklanadi: qayta ishga tushganda ham lot to'g'ri bo'ladi         |
//+------------------------------------------------------------------+
void TarixdanTiklash()
  {
   datetime hozir = TimeCurrent();
   datetime kun   = KunBoshi(hozir);
   datetime dan   = (datetime)((long)kun - (long)TarixKunlar * 86400);
   if(!HistorySelect(dan, hozir + 3600))
     {
      Print("XATO: HistorySelect bajarilmadi, keyingi tickda qayta uriniladi");
      return;
     }

   ulong    idlar[];
   double   soflar[];
   datetime yopVaqt[];
   int      k = 0;
   int      n = HistoryDealsTotal();

   for(int i = 0; i < n; i++)
     {
      ulong d = HistoryDealGetTicket(i);
      if(d == 0)
         continue;
      if((ulong)HistoryDealGetInteger(d, DEAL_MAGIC) != MagicNumber)
         continue;
      if(HistoryDealGetString(d, DEAL_SYMBOL) != _Symbol)
         continue;   // har juftlik o'z siklini yuritadi
      if(HistoryDealGetInteger(d, DEAL_ENTRY) != DEAL_ENTRY_IN)
         continue;
      ulong pid = (ulong)HistoryDealGetInteger(d, DEAL_POSITION_ID);
      if(Indeks(idlar, k, pid) >= 0)
         continue;
      ArrayResize(idlar, k + 1, 64);
      ArrayResize(soflar, k + 1, 64);
      ArrayResize(yopVaqt, k + 1, 64);
      idlar[k]   = pid;
      soflar[k]  = 0.0;
      yopVaqt[k] = 0;
      k++;
     }

   for(int i = 0; i < n; i++)
     {
      ulong d = HistoryDealGetTicket(i);
      if(d == 0)
         continue;
      int idx = Indeks(idlar, k, (ulong)HistoryDealGetInteger(d, DEAL_POSITION_ID));
      if(idx < 0)
         continue;
      soflar[idx] += HistoryDealGetDouble(d, DEAL_PROFIT)
                     + HistoryDealGetDouble(d, DEAL_SWAP)
                     + HistoryDealGetDouble(d, DEAL_COMMISSION)
                     + HistoryDealGetDouble(d, DEAL_FEE);
      long e = HistoryDealGetInteger(d, DEAL_ENTRY);
      if(e == DEAL_ENTRY_OUT || e == DEAL_ENTRY_OUT_BY || e == DEAL_ENTRY_INOUT)
        {
         datetime dt = (datetime)HistoryDealGetInteger(d, DEAL_TIME);
         if(dt > yopVaqt[idx])
            yopVaqt[idx] = dt;
        }
     }

   int tartib[];
   int m = 0;
   for(int i = 0; i < k; i++)
     {
      if(yopVaqt[i] == 0)
         continue;
      ArrayResize(tartib, m + 1, 64);
      tartib[m] = i;
      m++;
     }
   for(int i = 1; i < m; i++)
     {
      int j   = i;
      int tmp = tartib[i];
      while(j > 0 && yopVaqt[tartib[j - 1]] > yopVaqt[tmp])
        {
         tartib[j] = tartib[j - 1];
         j--;
        }
      tartib[j] = tmp;
     }

   int      qadam   = 0;
   double   sikl    = 0.0;
   int      xato    = 0;
   int      kunS    = 0;
   double   kunN    = 0.0;
   datetime pauza   = 0;
   datetime oxirgi  = 0;
   for(int i = 0; i < m; i++)
     {
      int    idx = tartib[i];
      double s   = soflar[idx];
      if(yopVaqt[idx] >= kun)
        {
         kunS++;
         kunN += s;
        }
      if(s < 0.0)
        {
         sikl -= s;
         qadam++;
         if(qadam >= MaxQadam)
           {
            // sikl muvaffaqiyatsiz: zarar qabul qilinadi, pauza, baza lotga qaytish
            pauza = yopVaqt[idx] + PauzaSoat * 3600;
            qadam = 0;
            sikl  = 0.0;
            xato++;
           }
        }
      else
        {
         sikl -= s;
         if(sikl <= 0.0)
           {
            sikl  = 0.0;
            qadam = 0;
           }
        }
      if(yopVaqt[idx] > oxirgi)
         oxirgi = yopVaqt[idx];
     }

   g_qadam           = qadam;
   g_siklZarar       = sikl;
   g_muvaffaqiyatsiz = xato;
   g_kunSavdo        = kunS;
   g_kunNatija       = kunN;
   g_pauzaGacha      = pauza;
   if(oxirgi > g_oxirgiYopilish)
      g_oxirgiYopilish = oxirgi;
   g_kunBoshi      = kun;
   g_oxirgiTiklash = hozir;
   g_tarixYangila  = false;
  }

//+------------------------------------------------------------------+
//| Freeze level tekshiruvi (tanlangan pozitsiya uchun)              |
//+------------------------------------------------------------------+
bool FreezeOK()
  {
   double freeze = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL) * _Point;
   if(freeze <= 0.0)
      return true;
   MqlTick t;
   if(!SymbolInfoTick(_Symbol, t))
      return false;
   double sl = PositionGetDouble(POSITION_SL);
   if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
      return !(sl > 0.0 && t.bid - sl <= freeze);
   return !(sl > 0.0 && sl - t.ask <= freeze);
  }

//+------------------------------------------------------------------+
//| Pozitsiyani yopish (3 martagacha qayta urinish)                  |
//+------------------------------------------------------------------+
bool Yopish(const ulong ticket, const string sabab)
  {
   for(int u = 1; u <= MaxUrinishlar; u++)
     {
      if(!PositionSelectByTicket(ticket))
         return true;
      if(!FreezeOK())
        {
         PrintFormat("Yopish kechiktirildi (%s): narx freeze level ichida", sabab);
         return false;
        }
      bool ok = g_savdo.PositionClose(ticket, (ulong)MaxSlippagePunkt);
      uint rc = g_savdo.ResultRetcode();
      if(ok && (rc == TRADE_RETCODE_DONE || rc == TRADE_RETCODE_DONE_PARTIAL || rc == TRADE_RETCODE_PLACED))
        {
         PrintFormat("Pozitsiya #%I64u yopildi. Sabab: %s", ticket, sabab);
         g_oxirgiYopilish = TimeCurrent();
         g_tarixYangila   = true;
         return true;
        }
      PrintFormat("XATO: yopish #%I64u urinish %d/%d, retcode=%u (%s)", ticket, u, MaxUrinishlar, rc, g_savdo.ResultRetcodeDescription());
      if(!QaytaUrinish(rc))
         return false;
      Sleep(500);
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Komissiya bahosi (hisob valyutasida, manfiy son)                 |
//+------------------------------------------------------------------+
double PozitsiyaKomissiyasi(const ulong posId, const double hajm, const int ushlab)
  {
   if(g_komPozId == posId && g_komAniq)
      return g_komQiymat;
   double c = 0.0;
   if(HistorySelectByPosition((long)posId))
     {
      int n = HistoryDealsTotal();
      for(int i = 0; i < n; i++)
        {
         ulong d = HistoryDealGetTicket(i);
         if(d == 0)
            continue;
         if(HistoryDealGetInteger(d, DEAL_ENTRY) == DEAL_ENTRY_IN)
            c += HistoryDealGetDouble(d, DEAL_COMMISSION) + HistoryDealGetDouble(d, DEAL_FEE);
        }
     }
   g_tarixYangila = true;
   double natija = (c != 0.0) ? c * 2.0 : -KomissiyaUSDLot * g_koef * hajm;
   g_komPozId  = posId;
   g_komQiymat = natija;
   g_komAniq   = (c != 0.0 || ushlab >= 10);
   return natija;
  }

//--- Dam olish kunlari yopiladigan bozorlarda: juma kechqurun pozitsiyani yopish (gap xavfi).
//--- Kripto kabi 7 kun ishlaydigan juftliklarga ta'sir qilmaydi.
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
//| Ochiq pozitsiyani boshqarish                                     |
//+------------------------------------------------------------------+
void PozitsiyaniBoshqar(const ulong ticket)
  {
   if(!PositionSelectByTicket(ticket))
      return;
   ulong posId = (ulong)PositionGetInteger(POSITION_IDENTIFIER);

   if(PositionGetDouble(POSITION_SL) <= 0.0)
     {
      Print("DIQQAT: pozitsiyada stop-loss yo'q! Darhol yopiladi.");
      Yopish(ticket, "SL yo'q");
      return;
     }

   // Maqsad: sikldagi oldingi zararlarni qoplash + baza xavf x TPKoef
   if(g_tpPozId != posId)
     {
      g_tpMaqsad = g_siklZarar + BazaRisk() * TPKoef;
      g_tpPozId  = posId;
     }

   double   hajm     = PositionGetDouble(POSITION_VOLUME);
   double   foyda    = PositionGetDouble(POSITION_PROFIT);
   double   svop     = PositionGetDouble(POSITION_SWAP);
   datetime ochilgan = (datetime)PositionGetInteger(POSITION_TIME);
   int      ushlab   = (int)(TimeCurrent() - ochilgan);
   double   kom      = PozitsiyaKomissiyasi(posId, hajm, ushlab);
   if(!PositionSelectByTicket(ticket))
      return;
   double   sof      = foyda + svop + kom;
   g_ochiqSof = sof;

   if(ushlab < MinHoldSeconds)
     {
      if(sof >= g_tpMaqsad)
         g_holatMatn = StringFormat("TP yetdi, MinHold kutilmoqda (%d/%d s)", ushlab, MinHoldSeconds);
      return;
     }
   if(JumaYopishVaqti())
     {
      Yopish(ticket, "Juma yopilishi");
      return;
     }
   if(sof >= g_tpMaqsad)
     {
      Yopish(ticket, StringFormat("Sikl maqsadi: sof %.2f", sof));
      return;
     }
   if(MaxUshlabSoat > 0 && ushlab >= MaxUshlabSoat * 3600)
      Yopish(ticket, StringFormat("Vaqt chegarasi: %d soat", MaxUshlabSoat));
  }

//+------------------------------------------------------------------+
//| Yangi savdoga ruxsat                                             |
//+------------------------------------------------------------------+
bool SavdoRuxsat(string &sabab)
  {
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED))
     {
      sabab = "Avtosavdo o'chirilgan";
      return false;
     }
   if(SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE) != SYMBOL_TRADE_MODE_FULL)
     {
      sabab = "Juftlikda savdo cheklangan";
      return false;
     }
   datetime hozir = TimeCurrent();
   MqlDateTime t;
   TimeToStruct(hozir, t);
   if(!SessiyaOchiq())
     {
      sabab = "Juftlik sessiyasi yopiq yoki yopilishiga oz qoldi";
      return false;
     }
   if(HaftaOxiriYopiq() && t.day_of_week == 5 && t.hour >= CloseFridayHour - 1)
     {
      sabab = "Juma, savdo tugagan";
      return false;
     }
   if(t.hour < SavdoBoshSoat || t.hour >= SavdoOxirSoat)
     {
      sabab = StringFormat("Savdo vaqti emas (%02d:00-%02d:00)", SavdoBoshSoat, SavdoOxirSoat);
      return false;
     }
   if(RolloverniOtkazish)
     {
      bool rollover = (RolloverBoshSoat > RolloverOxirSoat)
                      ? (t.hour >= RolloverBoshSoat || t.hour < RolloverOxirSoat)
                      : (t.hour >= RolloverBoshSoat && t.hour < RolloverOxirSoat);
      if(rollover)
        {
         sabab = "Rollover oralig'i (spred keng)";
         return false;
        }
     }
   if(JamiOchiq() >= MaxOchiqPozitsiya)
     {
      sabab = StringFormat("Hisobda %d ta pozitsiya ochiq (limit %d)", JamiOchiq(), MaxOchiqPozitsiya);
      return false;
     }
   if(UmumiyLimitYetdi())
     {
      sabab = StringFormat("UMUMIY ZARAR LIMITI: balans eng yuqori %.2f dan %.0f%% tushdi. Savdo to'xtatildi.",
                           g_choqqi, UmumiyZararFoiz);
      return false;
     }
   if(g_pauzaGacha > hozir)
     {
      sabab = "Sikl muvaffaqiyatsiz, pauza: " + TimeToString(g_pauzaGacha, TIME_DATE | TIME_MINUTES) + " gacha";
      return false;
     }
   if(g_oxirgiYopilish > 0)
     {
      int sh = iBarShift(_Symbol, SIGNAL_TF, g_oxirgiYopilish, false);
      if(sh >= 0 && sh < CooldownBars)
        {
         sabab = StringFormat("Cooldown: %d/%d sham", sh, CooldownBars);
         return false;
        }
     }
   sabab = "";
   return true;
  }

//+------------------------------------------------------------------+
//| Signal: H1 EMA50 trend yo'nalishida, har yangi M15 shamda        |
//+------------------------------------------------------------------+
int SignalHisobla(double &sl)
  {
   sl = 0.0;
   double  e[], atr[];
   MqlRates h[];
   ArraySetAsSeries(h, true);
   if(!Bufer(g_hEma, 0, 1, 4, e) || !Bufer(g_hAtr, 0, 1, 1, atr) || atr[0] <= 0.0)
      return 0;
   if(CopyRates(_Symbol, TREND_TF, 1, 1, h) < 1)
      return 0;
   int yon = 0;
   if(h[0].close > e[0] && e[0] > e[3])
      yon = 1;
   else
      if(h[0].close < e[0] && e[0] < e[3])
         yon = -1;
   if(TeskariSignal)
      yon = -yon;
   if(yon != 0)
      sl = atr[0] * SLATRKoef;
   return yon;
  }

//+------------------------------------------------------------------+
//| Lot: SL ga tegsa aynan berilgan xavf yo'qolsin                   |
//+------------------------------------------------------------------+
double LotHisobla(const int yon, const double narx, const double sl, const double risk)
  {
   double p1 = 0.0;
   if(!OrderCalcProfit(yon > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, _Symbol, 1.0, narx, sl, p1))
     {
      PrintFormat("XATO: OrderCalcProfit bajarilmadi, kod %d", GetLastError());
      return 0.0;
     }
   double zarar1 = MathAbs(p1) + KomissiyaUSDLot * g_koef;
   if(zarar1 <= 0.0)
      return 0.0;
   double minL  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxL  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double qadam = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(qadam <= 0.0)
      qadam = minL;
   double lot = MathFloor(risk / zarar1 / qadam + 1e-9) * qadam;
   lot = NormalizeDouble(lot, LotRaqamlar(qadam));
   if(lot < minL)
     {
      PrintFormat("Savdo ochilmaydi: minimal lot %.2f da SL zarari %.2f > ruxsat etilgan xavf %.2f",
                  minL, zarar1 * minL, risk);
      return 0.0;
     }
   if(lot > maxL)
      lot = maxL;
   double marja = 0.0;
   if(OrderCalcMargin(yon > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, _Symbol, lot, narx, marja)
      && marja > AccountInfoDouble(ACCOUNT_MARGIN_FREE) * 0.9)
     {
      PrintFormat("Savdo ochilmaydi: marja yetarli emas (kerak %.2f, bo'sh %.2f)", marja, AccountInfoDouble(ACCOUNT_MARGIN_FREE));
      return 0.0;
     }
   return lot;
  }

//+------------------------------------------------------------------+
//| Pozitsiya ochish: SL buyruq bilan birga serverga yuboriladi      |
//+------------------------------------------------------------------+
bool Ochish(const int yon, const double masofa)
  {
   for(int u = 1; u <= MaxUrinishlar; u++)
     {
      string belgi;
      if(OzPozitsiya(belgi) != 0)
         return true;
      MqlTick t;
      if(!SymbolInfoTick(_Symbol, t))
        {
         Sleep(300);
         continue;
        }
      double spred  = t.ask - t.bid;
      double stops  = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
      double freeze = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL) * _Point;
      double minM   = MathMax((double)MinSLPunkt * _Point,
                              MathMax(spred * MinSLSpredKoef, MathMax(stops, freeze) + spred + _Point));
      double m      = MathMax(masofa, minM);
      double narx   = (yon > 0) ? t.ask : t.bid;
      double sl     = NormNarx(yon > 0 ? narx - m : narx + m);

      if((yon > 0 && t.bid - sl <= stops) || (yon < 0 && sl - t.ask <= stops))
        {
         PrintFormat("Savdo ochilmaydi: SL stops level (%.0f punkt) ga juda yaqin", stops / _Point);
         return false;
        }
      double risk = QadamRisk();
      double lot  = LotHisobla(yon, narx, sl, risk);
      if(lot <= 0.0)
         return false;

      string izoh = StringFormat("KMU q%d %s", g_qadam + 1, yon > 0 ? "buy" : "sell");
      bool ok = (yon > 0) ? g_savdo.Buy(lot, _Symbol, narx, sl, 0.0, izoh)
                          : g_savdo.Sell(lot, _Symbol, narx, sl, 0.0, izoh);
      uint rc = g_savdo.ResultRetcode();
      if(ok && (rc == TRADE_RETCODE_DONE || rc == TRADE_RETCODE_DONE_PARTIAL || rc == TRADE_RETCODE_PLACED))
        {
         PrintFormat("Ochildi: qadam %d/%d, %s %.2f lot, SL %.0f punkt, xavf %.2f, qoplanadigan zarar %.2f",
                     g_qadam + 1, MaxQadam, yon > 0 ? "BUY" : "SELL", lot, MathAbs(narx - sl) / _Point, risk, g_siklZarar);
         g_tpPozId = 0;
         g_komAniq = false;
         return true;
        }
      PrintFormat("XATO: ochish urinish %d/%d, retcode=%u (%s)", u, MaxUrinishlar, rc, g_savdo.ResultRetcodeDescription());
      if(!QaytaUrinish(rc))
         return false;
      Sleep(500);
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Kirishni tekshirish (yangi M15 sham boshida)                     |
//+------------------------------------------------------------------+
void KirishniTekshir()
  {
   string sabab;
   if(!SavdoRuxsat(sabab))
     {
      g_holatMatn = sabab;
      return;
     }
   datetime bar = iTime(_Symbol, SIGNAL_TF, 0);
   if(bar == 0)
      return;
   if(bar != g_signalBar)
     {
      g_signalBar     = bar;
      g_barIshlatildi = false;
      g_barSignal     = SignalHisobla(g_barSLMasofa);
     }
   if(g_barSignal == 0 || g_barIshlatildi)
     {
      g_holatMatn = "Signal kutilmoqda";
      return;
     }
   if(TimeCurrent() - bar > KirishOynasiSoniya)
     {
      g_holatMatn = "Signal eskirdi, keyingi sham kutilmoqda";
      return;
     }
   // Spred filtri SL masofasiga nisbatan: har qanday juftlikda (oltin, neft, BTC, indeks) ishlaydi
   int    spred      = JoriySpred();
   double spredFoiz  = (g_barSLMasofa > 0.0) ? spred * _Point / g_barSLMasofa * 100.0 : 100.0;
   if(spredFoiz > MaxSpreadSLFoiz || (MaxSpreadPoints > 0 && spred > MaxSpreadPoints))
     {
      g_holatMatn = StringFormat("Spred katta: %d punkt = SL ning %.0f%% (limit %.0f%%)", spred, spredFoiz, MaxSpreadSLFoiz);
      return;
     }
   g_barIshlatildi = true;
   // Lot sikl qadamiga bog'liq: ochishdan oldin holatni tarixdan albatta yangilaymiz
   TarixdanTiklash();
   if(!SavdoRuxsat(sabab))
     {
      g_holatMatn = sabab;
      return;
     }
   Ochish(g_barSignal, g_barSLMasofa);
  }

//+------------------------------------------------------------------+
//| Grafikdagi holat paneli                                          |
//+------------------------------------------------------------------+
void GrafikniYangila(const bool pozBor)
  {
   if(!GrafikdaKorsatish)
      return;
   if(MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE))
      return;
   static datetime oxirgi = 0;
   if(TimeCurrent() == oxirgi)
      return;
   oxirgi = TimeCurrent();

   string val     = AccountInfoString(ACCOUNT_CURRENCY);
   double balans  = AccountInfoDouble(ACCOUNT_BALANCE);
   double tushish = (g_choqqi > 0.0) ? (g_choqqi - balans) / g_choqqi * 100.0 : 0.0;
   string pauza   = (g_pauzaGacha > TimeCurrent())
                    ? "HA, " + TimeToString(g_pauzaGacha, TIME_DATE | TIME_MINUTES) + " gacha"
                    : "yo'q";
   string m = "=== KvantMartinUz v2 TESKARI (YUQORI XAVF) === " + _Symbol + "\n";
   m += StringFormat("Balans: %.2f %s (~%.2f USD)\n", balans, val, USD(balans));
   m += StringFormat("Hisobda ochiq pozitsiyalar (barcha juftliklar): %d / %d\n", JamiOchiq(), MaxOchiqPozitsiya);
   m += StringFormat("Sikl qadami: %d / %d   Keyingi savdo xavfi: %.2f %s\n", g_qadam + 1, MaxQadam, QadamRisk(), val);
   m += StringFormat("Qoplanadigan zarar: %.2f %s\n", g_siklZarar, val);
   m += StringFormat("To'liq muvaffaqiyatsiz sikl zarari: ~%.1f%% balans\n", MaxSiklFoiz());
   m += StringFormat("Muvaffaqiyatsiz sikllar (%d kun): %d\n", TarixKunlar, g_muvaffaqiyatsiz);
   m += StringFormat("Bugun: %d savdo, natija %.2f %s\n", g_kunSavdo, g_kunNatija, val);
   m += StringFormat("Eng yuqori balansdan tushish: %.1f%% / %.0f%%%s\n", tushish, UmumiyZararFoiz,
                     UmumiyLimitYetdi() ? "  -> TO'XTATILGAN" : "");
   m += "Pauza: " + pauza + "\n";
   m += StringFormat("Spred: %d punkt  Sessiya: %s\n", JoriySpred(), SessiyaOchiq() ? "ochiq" : "yopiq");
   if(pozBor)
      m += StringFormat("Ochiq pozitsiya: %.2f %s (maqsad +%.2f)\n", g_ochiqSof, val, g_tpMaqsad);
   else
      m += "Ochiq pozitsiya: yo'q\n";
   m += "Holat: " + g_holatMatn;
   Comment(m);
  }

//+------------------------------------------------------------------+
//| Ishga tushirish                                                  |
//+------------------------------------------------------------------+
int OnInit()
  {
   if(BazaRiskFoiz <= 0.0 || MaxQadam < 1 || MaxQadam > 7)
     {
      Print("XATO: BazaRiskFoiz > 0 va MaxQadam 1-7 oralig'ida bo'lishi kerak");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(MaxSiklFoiz() > 50.0)
     {
      PrintFormat("XATO: to'liq muvaffaqiyatsiz sikl zarari %.1f%% > 50%%. BazaRiskFoiz yoki MaxQadam ni kamaytiring.", MaxSiklFoiz());
      return INIT_PARAMETERS_INCORRECT;
     }
   if(TPKoef < 0.5 || TPKoef > 3.0 || UmumiyZararFoiz <= 0.0 || UmumiyZararFoiz > 80.0
      || MaxUrinishlar < 1 || MaxUrinishlar > 3 || PauzaSoat < 0 || CooldownBars < 0
      || MinHoldSeconds < 0 || TarixKunlar < 1 || SLATRKoef <= 0.0 || SavdoBoshSoat >= SavdoOxirSoat
      || SavdoBoshSoat < 0 || SavdoOxirSoat > 24 || MaxOchiqPozitsiya < 1 || MaxSpreadSLFoiz <= 0.0)
     {
      Print("XATO: parametrlar noto'g'ri");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(!KoeffitsientAniqla())
      return INIT_FAILED;

   g_savdo.SetExpertMagicNumber(MagicNumber);
   g_savdo.SetDeviationInPoints((ulong)MaxSlippagePunkt);
   g_savdo.SetMarginMode();
   g_savdo.LogLevel(LOG_LEVEL_ERRORS);
   if(!g_savdo.SetTypeFillingBySymbol(_Symbol))
      Print("DIQQAT: to'ldirish turini aniqlab bo'lmadi, standart qiymat ishlatiladi");

   g_hEma = iMA(_Symbol, TREND_TF, TREND_EMA, 0, MODE_EMA, PRICE_CLOSE);
   g_hAtr = iATR(_Symbol, SIGNAL_TF, ATR_DAVR);
   if(g_hEma == INVALID_HANDLE || g_hAtr == INVALID_HANDLE)
     {
      Print("XATO: indikatorlarni yaratib bo'lmadi");
      return INIT_FAILED;
     }

   if(UmumiyLimitniTiklash || MQLInfoInteger(MQL_TESTER))
      GlobalVariableDel(ChoqqiNomi());
   g_choqqi = GlobalVariableCheck(ChoqqiNomi()) ? GlobalVariableGet(ChoqqiNomi()) : 0.0;
   ChoqqiYangila();

   TarixdanTiklash();
   PrintFormat("Ishga tushdi (YUQORI XAVF): %s, baza xavf %.2f%%, max qadam %d, muvaffaqiyatsiz sikl ~%.1f%%, umumiy limit %.0f%%",
               _Symbol, BazaRiskFoiz, MaxQadam, MaxSiklFoiz(), UmumiyZararFoiz);
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   if(g_hEma != INVALID_HANDLE)
      IndicatorRelease(g_hEma);
   if(g_hAtr != INVALID_HANDLE)
      IndicatorRelease(g_hAtr);
   Comment("");
   PrintFormat("To'xtatildi, sabab kodi %d", reason);
  }

//+------------------------------------------------------------------+
//| Har bir tick                                                     |
//+------------------------------------------------------------------+
void OnTick()
  {
   datetime hozir = TimeCurrent();
   if(KunBoshi(hozir) != g_kunBoshi || g_tarixYangila || hozir - g_oxirgiTiklash >= 60)
      TarixdanTiklash();
   ChoqqiYangila();

   string belgi;
   ulong  pos = OzPozitsiya(belgi);

   if(pos != 0)
     {
      g_oldingiPozBor = true;
      if(belgi == _Symbol)
         PozitsiyaniBoshqar(pos);
      else
         g_holatMatn = "Boshqa juftlikda ochiq pozitsiya bor: " + belgi;
     }
   else
     {
      g_ochiqSof = 0.0;
      if(g_oldingiPozBor)
        {
         // pozitsiya yopildi: sikl holatini darhol tarixdan yangilaymiz, shu tickda kirmaymiz
         g_oldingiPozBor = false;
         TarixdanTiklash();
         if(hozir > g_oxirgiYopilish)
            g_oxirgiYopilish = hozir;
         g_holatMatn = "Pozitsiya yopildi, cooldown";
        }
      else
         KirishniTekshir();
     }
   GrafikniYangila(pos != 0);
  }

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
      g_tarixYangila = true;
  }
//+------------------------------------------------------------------+
