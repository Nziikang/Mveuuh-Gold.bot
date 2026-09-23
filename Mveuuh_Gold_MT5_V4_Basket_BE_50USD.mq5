//+------------------------------------------------------------------+
//| mveuuh_Gold_MT5.mq5                                              |
//| mveuuh Gold - Adaptive trend pyramid / basket EA (MT5)           |
//| Necessite un compte en mode HEDGING (plusieurs positions         |
//| simultanees dans le meme sens).                                  |
//+------------------------------------------------------------------+
#property strict
#property version "3.10"

#include <Trade\Trade.mqh>
CTrade trade;

input string Inp01="=== GENERAL ===";
input string BotName="mveuuh Gold";
input string TradeComment="mveuuh 237";
input ulong  MagicNumber=20260920;
input bool   OnlyThisSymbol=true;
input bool   CompteProtection=true;
input bool   AllowLiveTrading=false;

input string Inp02="=== TREND FILTER ===";
input ENUM_TIMEFRAMES TrendTF=PERIOD_H1;
input int FastEMA=8;
input int MidEMA=21;
input int SlowEMA=50;
input bool UseADXFilter=true;
input int ADXPeriod=14;
input double MinADX=14.0;
input bool RequirePriceBeyondFastEMA=true;

input string Inp03="=== ENTRY / PYRAMID ===";
input double BaseLot=0.10;
input bool AggressiveLotMode=true;
input double AggressiveLotStart=0.10;
input double AggressiveLotMultiplier=1.80;
input double AggressiveLotMax=10.00;
input bool CapitalRiskScaling=true;
input double CapitalStepUSD=100.0;
input double CapitalLotMultiplier=1.25;
input double TrendRiskMultiplier=1.50;
input double WeakTrendMultiplier=0.70;
input double MaxCapitalScale=8.00;

input bool AllowLargeLots=true;
input double LotMultiplier=1.5;
input double GridStepPips=6.0;
input int MaxPositions=20;
input double MaxLotPerOrder=10.0;
input double MaxTotalLots=40.0;
input int MaxAddsPerBar=1;
input bool AllowNewBasketOnlyOnNewBar=false;
input int MinSecondsBetweenAdds=15;

input string Inp04="=== BASKET MANAGEMENT ===";
input int InitialBasketPositions=10;
input double BasketPositionLot=0.10;
input double BE_StartPerPositionUSD=100.0;
input double BE_StepPerPositionUSD=50.0;
input double BE_LockPerPositionUSD=50.0;
input bool TargetPercentEquity=false;
input double BasketTargetPercent=1.0;
input bool UseBasketStop=true;
input double BasketMaxLossUSD=150.0;
input bool UseEquityDrawdownStop=true;
input double MaxEquityDrawdownPercent=10.0;
input bool CloseOnTrendFlip=true;

input string Inp04b="=== GLOBAL PROFIT CIRCUIT BREAKER ===";
input bool   UseGlobalProfitTarget=false;
input bool   GlobalTargetIsPercent=false;
input double GlobalProfitTargetUSD=2000000.0;
input double GlobalProfitTargetPercent=100.0;
input bool   ResetTargetDaily=true;
input bool   StopEAAfterGlobalTarget=false;

input string Inp05="=== SAFETY ===";
input double MaxSpreadPips=80.0;
input double MinFreeMarginPercent=100.0;
input int Slippage=3;

input string Inp06="=== SESSION ===";
input bool UseSessionFilter=false;
input int SessionStartHour=0;
input int SessionEndHour=23;

input string Inp07="=== JOURNAL / PANEL ===";
input bool UseJournal=true;
input string JournalFile="mveuuh_Gold.csv";
input bool ShowDashboard=true;

input string Inp08="=== NEWS FILTER (calendrier MT5) ===";
input bool   UseNewsFilter=true;
input ENUM_CALENDAR_EVENT_IMPORTANCE NewsMinImpact=CALENDAR_IMPORTANCE_HIGH;
input int    NewsMinutesBefore=15;
input int    NewsMinutesAfter=15;
input bool   NewsBlockNewBasket=true;
input bool   NewsCloseExistingBasket=false;
input bool   NewsFilterAllCurrencies=false;

input string Inp09="=== CONFIGURATION MISE A JOUR ===";
input string CurrentVersion="1.00";
input string VersionURL="https://raw.githubusercontent.com/Nziikang/Mveuuh-Gold.bot/main/version.txt";
input string BotDownloadURL="https://raw.githubusercontent.com/Nziikang/Mveuuh-Gold.bot/main/mveuuh_Gold_MT5.ex5";
input bool   CheckUpdateOnStart=true;

int      g_dir=0;
int      g_count=0;
double   g_lastEntry=0.0;
datetime g_lastAddTime=0;
datetime g_lastBar=0;
double   g_startEquity=0.0;
double   g_initialEquity=0.0;
bool     g_tradingStopped=false;
int      g_currentDay=-1;

int      h_fastEMA, h_midEMA, h_slowEMA, h_adx;

//+------------------------------------------------------------------+
double Pip()
{
   if(_Digits==3 || _Digits==5) return _Point*10.0;
   return _Point;
}

//+------------------------------------------------------------------+
bool TradingAllowed(string &reason)
{
   reason="OK";
   ENUM_ACCOUNT_TRADE_MODE mode=(ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE);
   bool compte=(mode==ACCOUNT_TRADE_MODE_DEMO);

   if(CompteProtection && !compte) { reason="Compte LIVE bloque (CompteProtection)"; return false; }
   if(!AllowLiveTrading && !compte) { reason="Compte LIVE bloque (AllowLiveTrading=false)"; return false; }
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED)) { reason="AutoTrading/MQL trading interdit"; return false; }
   if(!(bool)AccountInfoInteger(ACCOUNT_TRADE_ALLOWED)) { reason="Trading du compte interdit"; return false; }
   if(SymbolInfoInteger(_Symbol,SYMBOL_TRADE_MODE)!=SYMBOL_TRADE_MODE_FULL) { reason="Symbole non tradable"; return false; }
   return true;
}

bool TradingAllowed()
{
   string reason;
   return TradingAllowed(reason);
}

//+------------------------------------------------------------------+
bool SpreadOK(string &reason)
{
   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double spreadPips=(ask-bid)/Pip();
   if(spreadPips>MaxSpreadPips)
   {
      reason="Spread trop eleve: "+DoubleToString(spreadPips,1)+" > "+DoubleToString(MaxSpreadPips,1);
      return false;
   }
   reason="OK";
   return true;
}

bool SpreadOK()
{
   string reason;
   return SpreadOK(reason);
}

//+------------------------------------------------------------------+
bool SessionOK()
{
   if(!UseSessionFilter) return true;
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(),dt);
   int h=dt.hour;
   if(SessionStartHour<=SessionEndHour)
      return h>=SessionStartHour && h<=SessionEndHour;
   return (h>=SessionStartHour || h<=SessionEndHour);
}

//+------------------------------------------------------------------+
bool PositionMatches(int i)
{
   ulong ticket=PositionGetTicket(i);
   if(ticket==0) return false;
   if(!PositionSelectByTicket(ticket)) return false;
   if(PositionGetInteger(POSITION_MAGIC)!=(long)MagicNumber) return false;
   if(OnlyThisSymbol && PositionGetString(POSITION_SYMBOL)!=_Symbol) return false;
   return true;
}

//+------------------------------------------------------------------+
int CountPositions(int type=-1)
{
   int n=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      if(!PositionMatches(i)) continue;
      long ptype=PositionGetInteger(POSITION_TYPE);
      if(ptype!=POSITION_TYPE_BUY && ptype!=POSITION_TYPE_SELL) continue;
      if(type!=-1 && ptype!=type) continue;
      n++;
   }
   return n;
}

//+------------------------------------------------------------------+
double TotalLots()
{
   double total=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      if(!PositionMatches(i)) continue;
      long ptype=PositionGetInteger(POSITION_TYPE);
      if(ptype!=POSITION_TYPE_BUY && ptype!=POSITION_TYPE_SELL) continue;
      total+=PositionGetDouble(POSITION_VOLUME);
   }
   return total;
}

//+------------------------------------------------------------------+
double BasketProfit()
{
   double p=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      if(!PositionMatches(i)) continue;
      long ptype=PositionGetInteger(POSITION_TYPE);
      if(ptype!=POSITION_TYPE_BUY && ptype!=POSITION_TYPE_SELL) continue;
      p+=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
   }
   return p;
}

//+------------------------------------------------------------------+
int BasketDirection()
{
   int buys=CountPositions(POSITION_TYPE_BUY);
   int sells=CountPositions(POSITION_TYPE_SELL);
   if(buys>0 && sells==0) return 1;
   if(sells>0 && buys==0) return -1;
   return 0;
}

//+------------------------------------------------------------------+
double LatestEntryPrice()
{
   datetime latest=0;
   double price=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      if(!PositionMatches(i)) continue;
      long ptype=PositionGetInteger(POSITION_TYPE);
      if(ptype!=POSITION_TYPE_BUY && ptype!=POSITION_TYPE_SELL) continue;
      datetime opentime=(datetime)PositionGetInteger(POSITION_TIME);
      if(opentime>latest)
      {
         latest=opentime;
         price=PositionGetDouble(POSITION_PRICE_OPEN);
      }
   }
   return price;
}

//+------------------------------------------------------------------+
bool TrendSignal(int &dir,string &reason)
{
   dir=0;
   double fBuf[1], mBuf[1], sBuf[1], aBuf[1];
   if(CopyBuffer(h_fastEMA,0,1,1,fBuf)<=0) { reason="EMA 8 indisponible"; return false; }
   if(CopyBuffer(h_midEMA,0,1,1,mBuf)<=0)  { reason="EMA 21 indisponible"; return false; }
   if(CopyBuffer(h_slowEMA,0,1,1,sBuf)<=0) { reason="EMA 50 indisponible"; return false; }

   double f=fBuf[0], m=mBuf[0], s=sBuf[0];
   bool up=(f>m && m>s);
   bool dn=(f<m && m<s);

   double adx=0.0;
   if(UseADXFilter)
   {
      if(CopyBuffer(h_adx,MAIN_LINE,1,1,aBuf)<=0) { reason="ADX indisponible"; return false; }
      adx=aBuf[0];
      if(adx<MinADX) { reason="ADX faible: "+DoubleToString(adx,1)+" < "+DoubleToString(MinADX,1); return false; }
   }

   if(RequirePriceBeyondFastEMA && (up || dn))
   {
      double price=(up)?SymbolInfoDouble(_Symbol,SYMBOL_BID):SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      if(up && price<f)  { reason="BUY refuse: prix en retracement sous EMA8"; return false; }
      if(dn && price>f)  { reason="SELL refuse: prix en retracement sur EMA8"; return false; }
   }

   if(up) {dir=1; reason="BUY: EMA8 > EMA21 > EMA50 + prix confirme | ADX="+DoubleToString(adx,1); return true;}
   if(dn) {dir=-1; reason="SELL: EMA8 < EMA21 < EMA50 + prix confirme | ADX="+DoubleToString(adx,1); return true;}
   reason="Pas d'alignement EMA 8/21/50";
   return false;
}

bool TrendSignal(int &dir)
{
   string reason;
   return TrendSignal(dir,reason);
}

//+------------------------------------------------------------------+
double NormalizeLot(double lot)
{
   double minLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double maxLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   if(step<=0) step=0.01;
   lot=MathMax(minLot,MathMin(maxLot,MathMin(lot,MaxLotPerOrder)));
   lot=MathFloor(lot/step+1e-8)*step;
   return NormalizeDouble(lot,2);
}

//+------------------------------------------------------------------+
double NextLot()
{
   int n=CountPositions();
   double lot=BaseLot*MathPow(LotMultiplier,n);
   double room=MaxTotalLots-TotalLots();
   if(room<=0) return 0;
   lot=MathMin(lot,room);
   return NormalizeLot(lot);
}

//+------------------------------------------------------------------+
bool MarginOK(ENUM_ORDER_TYPE type,double lot,string &reason)
{
   double price=(type==ORDER_TYPE_BUY)?SymbolInfoDouble(_Symbol,SYMBOL_ASK):SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double marginRequired=0;
   if(!OrderCalcMargin(type,_Symbol,lot,price,marginRequired)) { reason="OrderCalcMargin echoue"; return false; }
   double freeMargin=AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   if(freeMargin<=marginRequired) { reason="Marge libre insuffisante"; return false; }
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   double pct=(equity>0)?(freeMargin/equity)*100.0:0;
   if(pct<MinFreeMarginPercent) { reason="Marge libre "+DoubleToString(pct,0)+"% < "+DoubleToString(MinFreeMarginPercent,0)+"%"; return false; }
   reason="OK";
   return true;
}

bool MarginOK(ENUM_ORDER_TYPE type,double lot)
{
   string reason;
   return MarginOK(type,lot,reason);
}

//+------------------------------------------------------------------+
bool OpenOrder(int dir,double lot,string &reason)
{
   if(!TradingAllowed(reason)) return false;
   if(!SpreadOK(reason)) return false;
   if(!SessionOK()) { reason="Hors session"; return false; }
   if(CountPositions()>=MaxPositions) { reason="Nombre maximum de positions atteint"; return false; }
   if(lot<=0) { reason="Lot invalide"; return false; }

   ENUM_ORDER_TYPE type=(dir>0)?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
   if(!MarginOK(type,lot,reason)) return false;

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(Slippage);

   double price=(type==ORDER_TYPE_BUY)?SymbolInfoDouble(_Symbol,SYMBOL_ASK):SymbolInfoDouble(_Symbol,SYMBOL_BID);
   bool ok=false;
   if(type==ORDER_TYPE_BUY)
      ok=trade.Buy(lot,_Symbol,price,0,0,TradeComment);
   else
      ok=trade.Sell(lot,_Symbol,price,0,0,TradeComment);

   if(!ok)
   {
      reason="Ordre refuse: retcode="+IntegerToString((int)trade.ResultRetcode())+" "+trade.ResultRetcodeDescription();
      Print("OrderSend error=",GetLastError()," retcode=",trade.ResultRetcode()," ",trade.ResultRetcodeDescription());
      return false;
   }
   g_lastEntry=price;
   g_lastAddTime=TimeCurrent();
   reason="ORDRE OUVERT";
   Log("OPEN "+(type==ORDER_TYPE_BUY?"BUY ":"SELL ")+DoubleToString(lot,2)+" @ "+DoubleToString(price,_Digits));
   return true;
}

bool OpenOrder(int dir,double lot)
{
   string reason;
   return OpenOrder(dir,lot,reason);
}

//+------------------------------------------------------------------+
void CloseBasket(string reason)
{
   for(int pass=0;pass<2;pass++)
   {
      for(int i=PositionsTotal()-1;i>=0;i--)
      {
         if(!PositionMatches(i)) continue;
         long ptype=PositionGetInteger(POSITION_TYPE);
         if(ptype!=POSITION_TYPE_BUY && ptype!=POSITION_TYPE_SELL) continue;

         ulong ticket=PositionGetTicket(i);
         trade.SetDeviationInPoints(Slippage);
         if(!trade.PositionClose(ticket,Slippage))
            Print("OrderClose error=",GetLastError()," ticket=",ticket);
      }
   }
   Log("CLOSE BASKET | "+reason);
}

//+------------------------------------------------------------------+
bool NewBar()
{
   datetime b[1];
   if(CopyTime(_Symbol,TrendTF,0,1,b)<=0) return false;
   if(b[0]!=g_lastBar)
   {
      g_lastBar=b[0];
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
bool PriceAdvancedEnough(int dir)
{
   double last=LatestEntryPrice();
   if(last<=0) return false;
   double current=(dir>0)?SymbolInfoDouble(_Symbol,SYMBOL_BID):SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double pips=(dir>0)?(current-last)/Pip():(last-current)/Pip();
   return pips>=GridStepPips;
}

// Etat du panier : le nombre de positions est fixe pour calculer les paliers.
int g_basketPositions=0;
double g_bestProtectedProfit=-DBL_MAX;

int BasketBELevel(double profit)
{
   if(g_basketPositions<=0 || BE_StepPerPositionUSD<=0.0) return 0;
   double start=BE_StartPerPositionUSD*g_basketPositions;
   if(profit<start) return 0;
   return 1+(int)MathFloor((profit-start)/(BE_StepPerPositionUSD*g_basketPositions));
}

double BasketProtectedProfit(double profit)
{
   int level=BasketBELevel(profit);
   if(level<=0) return -DBL_MAX;
   return (BE_LockPerPositionUSD + (level-1)*BE_StepPerPositionUSD)*g_basketPositions;
}

//+------------------------------------------------------------------+
void ManageBasket()
{
   int dir=BasketDirection();
   if(dir==0) return;

   double p=BasketProfit();
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);

   // BE panier dynamique : pour 10 positions, activation a +1000$,
   // puis protection +500$, +1000$, +1500$... a chaque +500$ de panier.
   double protectedProfit=BasketProtectedProfit(p);
   if(protectedProfit>-DBL_MAX/2 && protectedProfit>g_bestProtectedProfit)
      g_bestProtectedProfit=protectedProfit;

   if(g_bestProtectedProfit>-DBL_MAX/2 && p<=g_bestProtectedProfit)
   {
      CloseBasket("BE PANIER SECURISE +"+DoubleToString(g_bestProtectedProfit,2));
      g_basketPositions=0;
      g_bestProtectedProfit=-DBL_MAX;
      return;
   }

   if(UseBasketStop && p<=-MathAbs(BasketMaxLossUSD))
   {
      CloseBasket("BASKET STOP "+DoubleToString(p,2));
      return;
   }

   if(UseEquityDrawdownStop && g_startEquity>0)
   {
      double dd=(g_startEquity-equity)/g_startEquity*100.0;
      if(dd>=MaxEquityDrawdownPercent)
      {
         CloseBasket("EQUITY DD "+DoubleToString(dd,2)+"%");
         return;
      }
   }

   if(CloseOnTrendFlip)
   {
      int signal=0;
      if(TrendSignal(signal) && signal!=dir && CountPositions()>0)
      {
         CloseBasket("TREND FLIP");
         return;
      }
   }

   if(CountPositions()>=MaxPositions) return;
   if(TotalLots()>=MaxTotalLots-0.0001) return;
   if(!PriceAdvancedEnough(dir)) return;
   if(TimeCurrent()-g_lastAddTime<MinSecondsBetweenAdds) return;

   double lot=MVEUUH_CapitalTrendLot();
   double room=MaxTotalLots-TotalLots();
   if(room<=0) return;
   lot=MathMin(lot,room);
   lot=NormalizeLot(lot);
   if(lot<=0) return;
   OpenOrder(dir,lot);
}

//+------------------------------------------------------------------+
string g_status="Initialisation...";

void StartBasket()
{
   int dir=0;
   string reason;
   if(!TrendSignal(dir,reason) || dir==0) { g_status="ENTREE: "+reason; return; }
   if(CountPositions()>0) { g_status="Position deja ouverte"; return; }
   g_startEquity=AccountInfoDouble(ACCOUNT_EQUITY);
   int qty=MathMax(1,InitialBasketPositions);
   double lot=NormalizeLot(BasketPositionLot);
   if(lot<=0) { g_status="Lot invalide"; return; }

   int opened=0;
   for(int k=0;k<qty;k++)
   {
      string r;
      if(OpenOrder(dir,lot,r)) opened++;
      else Log("ENTREE PANIER BLOQUEE position "+IntegerToString(k+1)+"/"+IntegerToString(qty)+" | "+r);
   }

   if(opened>0)
   {
      g_basketPositions=opened;
      g_bestProtectedProfit=-DBL_MAX;
      g_status=(dir>0?"BUY":"SELL")+" panier ouvert | "+IntegerToString(opened)+" x "+DoubleToString(lot,2)+" lot";
   }
   else g_status="ENTREE PANIER BLOQUEE";
}

//+------------------------------------------------------------------+
void Log(string s)
{
   Print("[",BotName,"] ",s);
   if(!UseJournal) return;
   int h=FileOpen(JournalFile,FILE_READ|FILE_WRITE|FILE_CSV|FILE_SHARE_READ,';');
   if(h==INVALID_HANDLE) return;
   FileSeek(h,0,SEEK_END);
   FileWrite(h,TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),s,
             AccountInfoDouble(ACCOUNT_BALANCE),AccountInfoDouble(ACCOUNT_EQUITY),
             BasketProfit(),TotalLots(),CountPositions());
   FileClose(h);
}

//+------------------------------------------------------------------+
void Dashboard()
{
   if(!ShowDashboard){Comment("");return;}
   int d=BasketDirection();
   string side=(d>0)?"BUY":(d<0)?"SELL":"NONE";
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   double target=(g_basketPositions>0 ? BE_StartPerPositionUSD*g_basketPositions : BE_StartPerPositionUSD*InitialBasketPositions);
   double freeMargin=AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double marginPct=(equity>0)?freeMargin/equity*100.0:0;
   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   ENUM_ACCOUNT_TRADE_MODE mode=(ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE);
   bool compte=(mode==ACCOUNT_TRADE_MODE_DEMO);

   string s="";
   s+="mveuuh Gold - MT5\n";
   s+="Symbol: "+_Symbol+" | TF: "+EnumToString(TrendTF)+"\n";
   s+="Basket: "+side+" | Pos: "+IntegerToString(CountPositions())+"/"+IntegerToString(MaxPositions)+"\n";
   s+="Lots: "+DoubleToString(TotalLots(),2)+"/"+DoubleToString(MaxTotalLots,2)+"\n";
   s+="P/L: $"+DoubleToString(BasketProfit(),2)+" | BE start: $"+DoubleToString(target,2)+" | BE lock: $"+DoubleToString(g_bestProtectedProfit>-DBL_MAX/2?g_bestProtectedProfit:0.0,2)+"\n";
   s+="Margin: "+DoubleToString(marginPct,0)+"% | Spread: "+DoubleToString((ask-bid)/Pip(),1)+" pips\n";
   s+="Mode: "+(compte?"DEMO":"LIVE")+" | LiveAllowed: "+(AllowLiveTrading?"YES":"NO")+"\n";
   s+="Status: "+g_status+"\n";
   int sig=0; string sigReason;
   TrendSignal(sig,sigReason);
   s+="Signal H1: "+(sig>0?"BUY":sig<0?"SELL":"NONE")+" | "+sigReason+"\n";
   s+="New basket on new H1 bar: "+(AllowNewBasketOnlyOnNewBar?"YES":"NO")+"\n";
   if(UseNewsFilter)
   {
      s+="News filter: ON | Prochaine: "+
         (g_nextNewsTime>0 ? g_nextNewsName+" @ "+TimeToString(g_nextNewsTime,TIME_DATE|TIME_MINUTES)
                            : "aucune dans la fenetre")+"\n";
   }
   if(UseGlobalProfitTarget)
   {
      double gain=equity-g_initialEquity;
      double targetUSD=GlobalTargetIsPercent?g_initialEquity*GlobalProfitTargetPercent/100.0:GlobalProfitTargetUSD;
      s+="Global P/L: $"+DoubleToString(gain,2)+" / Objectif: $"+DoubleToString(targetUSD,2)+
         (g_tradingStopped?" | STOPPE":"")+"\n";
   }
   if(g_updateStatus!="") s+="Version: "+g_updateStatus+"\n";
   s+="Comment: "+TradeComment;
   Comment(s);
}

//+------------------------------------------------------------------+

int MVEUUH_CountEntryDealsToday()
{
   int count=0;
   datetime start=StringToTime(TimeToString(TimeCurrent(),TIME_DATE));
   if(!HistorySelect(start,TimeCurrent())) return 0;
   int total=HistoryDealsTotal();
   for(int i=0;i<total;i++)
   {
      ulong ticket=HistoryDealGetTicket(i);
      if(ticket==0) continue;
      if(HistoryDealGetString(ticket,DEAL_SYMBOL)!=_Symbol) continue;
      if(HistoryDealGetInteger(ticket,DEAL_ENTRY)==DEAL_ENTRY_IN) count++;
   }
   return count;
}


double MVEUUH_TrendMultiplier()
{
   // Uses the EA's existing EMA handles when available; otherwise neutral.
   double fast[1], mid[1], slow[1];
   if(h_fastEMA==INVALID_HANDLE || h_midEMA==INVALID_HANDLE || h_slowEMA==INVALID_HANDLE)
      return 1.0;

   if(CopyBuffer(h_fastEMA,0,0,1,fast)<=0 ||
      CopyBuffer(h_midEMA,0,0,1,mid)<=0 ||
      CopyBuffer(h_slowEMA,0,0,1,slow)<=0)
      return 1.0;

   if(fast[0]>mid[0] && mid[0]>slow[0]) return TrendRiskMultiplier;
   if(fast[0]<mid[0] && mid[0]<slow[0]) return TrendRiskMultiplier;
   return WeakTrendMultiplier;
}

double MVEUUH_CapitalTrendLot()
{
   double base=MVEUUH_CalcAggressiveLot();
   if(!CapitalRiskScaling) return base;

   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity<=0.0 || CapitalStepUSD<=0.0) return base;

   double steps=MathFloor(equity/CapitalStepUSD);
   double capitalScale=MathPow(CapitalLotMultiplier,MathMax(0.0,steps-1.0));
   capitalScale=MathMin(capitalScale,MaxCapitalScale);

   double lot=base*capitalScale*MVEUUH_TrendMultiplier();

   double vmin=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double vmax=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);

   lot=MathMax(lot,vmin);
   lot=MathMin(lot,MathMin(vmax,AggressiveLotMax));
   if(step>0) lot=MathFloor(lot/step)*step;

   return NormalizeDouble(lot,2);
}

double MVEUUH_CalcAggressiveLot()
{
   double lot = AggressiveLotMode ? AggressiveLotStart : BaseLot;
   int level = MathMax(0,MVEUUH_CountEntryDealsToday()-1);

   if(AggressiveLotMode)
      lot *= MathPow(AggressiveLotMultiplier,level);

   if(AllowLargeLots)
      lot = MathMin(lot,AggressiveLotMax);
   else
      lot = MathMin(lot,BaseLot);

   double vmin=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double vmax=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);

   lot=MathMax(lot,vmin);
   lot=MathMin(lot,MathMin(vmax,AggressiveLotMax));
   if(step>0) lot=MathFloor(lot/step)*step;

   return NormalizeDouble(lot,2);
}

//+------------------------------------------------------------------+
// Filtre de news economiques base sur le calendrier natif MT5.
// Bloque (ou ferme) le trading autour des evenements a fort impact
// concernant la devise du symbole (ex: USD pour XAUUSD).
//+------------------------------------------------------------------+
datetime g_nextNewsTime=0;
string   g_nextNewsName="";

bool IsNewsBlackout(string &reason)
{
   reason="";
   if(!UseNewsFilter) return false;

   int spanSec=(NewsMinutesBefore+NewsMinutesAfter+5)*60;
   datetime from=TimeCurrent()-spanSec;
   datetime to  =TimeCurrent()+spanSec;

   string baseCcy   = SymbolInfoString(_Symbol,SYMBOL_CURRENCY_BASE);
   string profitCcy = SymbolInfoString(_Symbol,SYMBOL_CURRENCY_PROFIT);

   MqlCalendarValue values[];
   int total=CalendarValueHistory(values,from,to,NULL,NULL);

   g_nextNewsTime=0;
   g_nextNewsName="";
   datetime now=TimeCurrent();
   bool blackout=false;

   for(int i=0;i<total;i++)
   {
      MqlCalendarEvent event;
      if(!CalendarEventById(values[i].event_id,event)) continue;
      if((int)event.importance<(int)NewsMinImpact) continue;

      MqlCalendarCountry country;
      string ccy="";
      if(CalendarCountryById(event.country_id,country)) ccy=country.currency;

      if(!NewsFilterAllCurrencies && ccy!=baseCcy && ccy!=profitCcy) continue;

      datetime evTime=values[i].time;
      datetime winStart=evTime-NewsMinutesBefore*60;
      datetime winEnd  =evTime+NewsMinutesAfter*60;

      if(now>=winStart && now<=winEnd)
      {
         blackout=true;
         reason="NEWS "+ccy+" \""+event.name+"\" ("+EnumToString(event.importance)+") @ "+
                TimeToString(evTime,TIME_DATE|TIME_MINUTES);
      }

      // Garde en memoire la prochaine news bloquante a venir (pour le dashboard)
      if(evTime>=now && (g_nextNewsTime==0 || evTime<g_nextNewsTime))
      {
         g_nextNewsTime=evTime;
         g_nextNewsName=ccy+" "+event.name+" ("+EnumToString(event.importance)+")";
      }
   }
   return blackout;
}

bool IsNewsBlackout()
{
   string reason;
   return IsNewsBlackout(reason);
}

//+------------------------------------------------------------------+
//| CONFIGURATION MISE A JOUR                                         |
//+------------------------------------------------------------------+
string g_updateStatus="";

bool CheckForUpdates()
  {
   char post[], result[];
   string headers;
   string cookie=NULL;
   int timeout=5000;

// On recupere la derniere version sur GitHub
   int res=WebRequest("GET",VersionURL,cookie,NULL,timeout,post,0,result,headers);

   if(res==200)
     {
      string LatestVersion=CharArrayToString(result,0,WHOLE_ARRAY,CP_UTF8);
      StringTrimLeft(LatestVersion);
      StringTrimRight(LatestVersion);

      Print("Version actuelle: ",CurrentVersion," | Derniere version: ",LatestVersion);

      if(LatestVersion!=CurrentVersion)
        {
         Print(">>> NOUVELLE MISE A JOUR DISPONIBLE: ",LatestVersion," <<<");
         Alert("Robot Prime: Nouvelle version "+LatestVersion+" disponible !");
         g_updateStatus="MAJ DISPONIBLE: "+LatestVersion+" (vous avez "+CurrentVersion+") - "+BotDownloadURL;
         return true; // Il y a une maj
        }
      else
        {
         Print("Robot a jour.");
         g_updateStatus="A jour ("+CurrentVersion+")";
         return false;
        }
     }
   else
     {
      Print("Erreur check update: ",res," - N'oublie pas d'ajouter l'URL dans MT5 > Outils > Options > Conseillers Experts > Autoriser WebRequest");
      g_updateStatus="Erreur check update (code "+IntegerToString(res)+")";
      return false;
     }
  }

//+------------------------------------------------------------------+
int OnInit()
{
   if(AccountInfoDouble(ACCOUNT_BALANCE)<=0) return INIT_FAILED;

   if(CheckUpdateOnStart) CheckForUpdates();

   // Warn if account is in netting mode (pyramiding won't work as intended)
   if((ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE)!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
      Print("[",BotName,"] ATTENTION: ce compte n'est pas en mode Hedging. Le pyramidage (plusieurs positions dans le même sens) ne fonctionnera pas comme prévu.");

   h_fastEMA=iMA(_Symbol,TrendTF,FastEMA,0,MODE_EMA,PRICE_CLOSE);
   h_midEMA =iMA(_Symbol,TrendTF,MidEMA,0,MODE_EMA,PRICE_CLOSE);
   h_slowEMA=iMA(_Symbol,TrendTF,SlowEMA,0,MODE_EMA,PRICE_CLOSE);
   h_adx    =iADX(_Symbol,TrendTF,ADXPeriod);

   if(h_fastEMA==INVALID_HANDLE || h_midEMA==INVALID_HANDLE ||
      h_slowEMA==INVALID_HANDLE || h_adx==INVALID_HANDLE)
   {
      Print("Erreur création des indicateurs");
      return INIT_FAILED;
   }

   datetime b[1];
   if(CopyTime(_Symbol,TrendTF,0,1,b)>0) g_lastBar=b[0];

   g_startEquity=AccountInfoDouble(ACCOUNT_EQUITY);
   g_initialEquity=g_startEquity;
   g_tradingStopped=false;
   Log("START | balance="+DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE),2)+
       " | compte="+(((ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE)==ACCOUNT_TRADE_MODE_DEMO)?"YES":"NO"));
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(h_fastEMA!=INVALID_HANDLE) IndicatorRelease(h_fastEMA);
   if(h_midEMA!=INVALID_HANDLE)  IndicatorRelease(h_midEMA);
   if(h_slowEMA!=INVALID_HANDLE) IndicatorRelease(h_slowEMA);
   if(h_adx!=INVALID_HANDLE)     IndicatorRelease(h_adx);
   Comment("");
}

//+------------------------------------------------------------------+
bool CheckGlobalProfitTarget()
{
   if(!UseGlobalProfitTarget)
   {
      // Le filtre est désactivé : on garde quand même g_currentDay à jour
      // pour que ResetTargetDaily fonctionne correctement si réactivé plus tard.
      return false;
   }

   // --- Reset automatique au changement de jour civil (heure serveur du broker) ---
   if(ResetTargetDaily)
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(),dt);
      int today=dt.day + dt.mon*100 + dt.year*10000;
      if(g_currentDay!=today)
      {
         bool firstRun=(g_currentDay==-1);
         g_currentDay=today;
         g_initialEquity=AccountInfoDouble(ACCOUNT_EQUITY);
         g_tradingStopped=false;
         if(!firstRun) Log("NOUVEAU JOUR | reset objectif global | equity="+DoubleToString(g_initialEquity,2));
      }
   }

   if(g_tradingStopped) return true;

   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   double gain=equity-g_initialEquity;

   double targetUSD=GlobalTargetIsPercent
                     ? g_initialEquity*GlobalProfitTargetPercent/100.0
                     : GlobalProfitTargetUSD;

   if(targetUSD<=0) return false;

   if(gain>=targetUSD)
   {
      if(CountPositions()>0) CloseBasket("GLOBAL PROFIT TARGET ATTEINT: "+DoubleToString(gain,2));
      g_tradingStopped=true;
      g_status="OBJECTIF ATTEINT ("+DoubleToString(gain,2)+" $)"+
                (ResetTargetDaily?" - reprise demain":" - TRADING ARRETE");
      Log("GLOBAL TARGET REACHED | gain="+DoubleToString(gain,2)+" | equity="+DoubleToString(equity,2));
      if(StopEAAfterGlobalTarget && !ResetTargetDaily) ExpertRemove();
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
void OnTick()
{
   if(ShowDashboard) Dashboard();

   if(CheckGlobalProfitTarget()) return;

   string reason;
   if(!TradingAllowed(reason)) { g_status="TRADING BLOQUE: "+reason; return; }
   if(!SpreadOK(reason)) { g_status="ATTENTE: "+reason; return; }
   if(!SessionOK()) { g_status="ATTENTE: hors session"; return; }

   string newsReason;
   bool inNewsBlackout=IsNewsBlackout(newsReason);

   int n=CountPositions();

   if(inNewsBlackout && NewsCloseExistingBasket && n>0)
   {
      CloseBasket("NEWS FILTER: "+newsReason);
      n=0;
   }

   if(n>0)
      ManageBasket(); // BE / stop panier / trend flip restent actifs meme pendant une news
   else if(inNewsBlackout && NewsBlockNewBasket)
      g_status="ATTENTE: "+newsReason;
   else if(!AllowNewBasketOnlyOnNewBar || NewBar())
   {
      g_basketPositions=0;
      g_bestProtectedProfit=-DBL_MAX;
      StartBasket();
   }
   else
      g_status="ATTENTE nouvelle bougie H1";
}
//+------------------------------------------------------------------+
