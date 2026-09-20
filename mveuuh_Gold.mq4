//+------------------------------------------------------------------+
//| mveuuh_Gold.mq4                                 |
//| mveuuh Gold - Adaptive trend pyramid / basket EA (MT4)                  |
//| Demo-first version inspired by the supplied EURUSD screenshot.   |
//+------------------------------------------------------------------+
#property strict
#property version "2.00"

input string Inp01="=== GENERAL ===";
input string BotName="mveuuh Gold";
input string TradeComment="mveuuh 237";
input int    MagicNumber=20260920;
input bool   OnlyThisSymbol=true;

input string Inp02="=== TREND FILTER ===";
input ENUM_TIMEFRAMES TrendTF=PERIOD_H1;
input int FastEMA=8;
input int MidEMA=21;
input int SlowEMA=50;
input bool UseADXFilter=true;
input int ADXPeriod=14;
input double MinADX=18.0;

input string Inp03="=== ENTRY / PYRAMID ===";
input double BaseLot=0.10;
input double LotMultiplier=1.35;
input double GridStepPips=10.0;
input int MaxPositions=20;
input double MaxLotPerOrder=10.0;
input double MaxTotalLots=40.0;
input int MaxAddsPerBar=1;
input bool AllowNewBasketOnlyOnNewBar=true;
input int MinSecondsBetweenAdds=30;

input string Inp04="=== BASKET MANAGEMENT ===";
input double BasketTargetUSD=50.0;
input bool TargetPercentEquity=false;
input double BasketTargetPercent=1.0;
input bool UseBasketStop=true;
input double BasketMaxLossUSD=150.0;
input bool UseEquityDrawdownStop=true;
input double MaxEquityDrawdownPercent=10.0;
input bool CloseOnTrendFlip=false;

input string Inp05="=== SAFETY ===";
input double MaxSpreadPips=3.0;
input double MinFreeMarginPercent=200.0;
input int Slippage=3;
input bool DemoProtection=true;
input bool AllowLiveTrading=false;

input string Inp06="=== SESSION ===";
input bool UseSessionFilter=false;
input int SessionStartHour=0;
input int SessionEndHour=23;

input string Inp07="=== JOURNAL / PANEL ===";
input bool UseJournal=true;
input string JournalFile="mveuuh_Gold.csv";
input bool ShowDashboard=true;

int      g_dir=0;
int      g_count=0;
double   g_lastEntry=0.0;
datetime g_lastAddTime=0;
datetime g_lastBar=0;
double   g_startEquity=0.0;

double Pip()
{
   if(Digits==3 || Digits==5) return Point*10.0;
   return Point;
}

bool TradingAllowed()
{
   if(DemoProtection && !IsDemo()) return false;
   if(!AllowLiveTrading && !IsDemo()) return false;
   return IsTradeAllowed();
}

bool SpreadOK()
{
   double spreadPips=(Ask-Bid)/Pip();
   return spreadPips<=MaxSpreadPips;
}

bool SessionOK()
{
   if(!UseSessionFilter) return true;
   int h=TimeHour(TimeCurrent());
   if(SessionStartHour<=SessionEndHour)
      return h>=SessionStartHour && h<=SessionEndHour;
   return (h>=SessionStartHour || h<=SessionEndHour);
}

int CountPositions(int type=-1)
{
   int n=0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()!=MagicNumber) continue;
      if(OnlyThisSymbol && OrderSymbol()!=Symbol()) continue;
      if(OrderType()!=OP_BUY && OrderType()!=OP_SELL) continue;
      if(type!=-1 && OrderType()!=type) continue;
      n++;
   }
   return n;
}

double TotalLots()
{
   double total=0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()!=MagicNumber) continue;
      if(OnlyThisSymbol && OrderSymbol()!=Symbol()) continue;
      if(OrderType()!=OP_BUY && OrderType()!=OP_SELL) continue;
      total+=OrderLots();
   }
   return total;
}

double BasketProfit()
{
   double p=0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()!=MagicNumber) continue;
      if(OnlyThisSymbol && OrderSymbol()!=Symbol()) continue;
      if(OrderType()!=OP_BUY && OrderType()!=OP_SELL) continue;
      p+=OrderProfit()+OrderSwap()+OrderCommission();
   }
   return p;
}

int BasketDirection()
{
   int buys=CountPositions(OP_BUY);
   int sells=CountPositions(OP_SELL);
   if(buys>0 && sells==0) return 1;
   if(sells>0 && buys==0) return -1;
   return 0;
}

double LatestEntryPrice()
{
   datetime latest=0;
   double price=0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()!=MagicNumber) continue;
      if(OnlyThisSymbol && OrderSymbol()!=Symbol()) continue;
      if(OrderType()!=OP_BUY && OrderType()!=OP_SELL) continue;
      if(OrderOpenTime()>latest)
      {
         latest=OrderOpenTime();
         price=OrderOpenPrice();
      }
   }
   return price;
}

bool TrendSignal(int &dir)
{
   double f=iMA(Symbol(),TrendTF,FastEMA,0,MODE_EMA,PRICE_CLOSE,1);
   double m=iMA(Symbol(),TrendTF,MidEMA,0,MODE_EMA,PRICE_CLOSE,1);
   double s=iMA(Symbol(),TrendTF,SlowEMA,0,MODE_EMA,PRICE_CLOSE,1);

   bool up=(f>m && m>s);
   bool dn=(f<m && m<s);

   if(UseADXFilter)
   {
      double adx=iADX(Symbol(),TrendTF,ADXPeriod,PRICE_CLOSE,MODE_MAIN,1);
      if(adx<MinADX) { dir=0; return false; }
   }

   if(up) {dir=1; return true;}
   if(dn) {dir=-1; return true;}
   dir=0;
   return false;
}

double NormalizeLot(double lot)
{
   double minLot=MarketInfo(Symbol(),MODE_MINLOT);
   double maxLot=MarketInfo(Symbol(),MODE_MAXLOT);
   double step=MarketInfo(Symbol(),MODE_LOTSTEP);
   if(step<=0) step=0.01;
   lot=MathMax(minLot,MathMin(maxLot,MathMin(lot,MaxLotPerOrder)));
   lot=MathFloor(lot/step+1e-8)*step;
   return NormalizeDouble(lot,2);
}

double NextLot()
{
   int n=CountPositions();
   double lot=BaseLot*MathPow(LotMultiplier,n);
   double room=MaxTotalLots-TotalLots();
   if(room<=0) return 0;
   lot=MathMin(lot,room);
   return NormalizeLot(lot);
}

bool MarginOK(int type,double lot)
{
   double fm=AccountFreeMarginCheck(Symbol(),type,lot);
   if(fm<=0) return false;
   double pct=(AccountEquity()>0)?(fm/AccountEquity())*100.0:0;
   return pct>=MinFreeMarginPercent;
}

bool OpenOrder(int dir,double lot)
{
   if(!TradingAllowed() || !SpreadOK() || !SessionOK()) return false;
   if(CountPositions()>=MaxPositions) return false;
   if(lot<=0) return false;

   int type=(dir>0)?OP_BUY:OP_SELL;
   if(!MarginOK(type,lot)) return false;

   RefreshRates();
   double price=(type==OP_BUY)?Ask:Bid;
   ResetLastError();
   int ticket=OrderSend(Symbol(),type,lot,price,Slippage,0,0,TradeComment,MagicNumber,0,clrNONE);
   if(ticket<0)
   {
      Print("OrderSend error=",GetLastError());
      return false;
   }
   g_lastEntry=price;
   g_lastAddTime=TimeCurrent();
   Log("OPEN "+(type==OP_BUY?"BUY ":"SELL ")+DoubleToString(lot,2)+" @ "+DoubleToString(price,Digits));
   return true;
}

void CloseBasket(string reason)
{
   for(int pass=0;pass<2;pass++)
   {
      for(int i=OrdersTotal()-1;i>=0;i--)
      {
         if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
         if(OrderMagicNumber()!=MagicNumber) continue;
         if(OnlyThisSymbol && OrderSymbol()!=Symbol()) continue;
         int type=OrderType();
         if(type!=OP_BUY && type!=OP_SELL) continue;

         RefreshRates();
         double price=(type==OP_BUY)?Bid:Ask;
         ResetLastError();
         if(!OrderClose(OrderTicket(),OrderLots(),price,Slippage,clrNONE))
            Print("OrderClose error=",GetLastError()," ticket=",OrderTicket());
      }
   }
   Log("CLOSE BASKET | "+reason);
}

bool NewBar()
{
   datetime b=iTime(Symbol(),TrendTF,0);
   if(b!=g_lastBar)
   {
      g_lastBar=b;
      return true;
   }
   return false;
}

bool PriceAdvancedEnough(int dir)
{
   double last=LatestEntryPrice();
   if(last<=0) return false;
   double current=(dir>0)?Bid:Ask;
   double pips=(dir>0)?(current-last)/Pip():(last-current)/Pip();
   return pips>=GridStepPips;
}

void ManageBasket()
{
   int dir=BasketDirection();
   if(dir==0) return;

   double p=BasketProfit();
   double target=TargetPercentEquity ? AccountEquity()*BasketTargetPercent/100.0 : BasketTargetUSD;

   if(p>=target)
   {
      CloseBasket("TARGET +"+DoubleToString(p,2));
      return;
   }

   if(UseBasketStop && p<=-MathAbs(BasketMaxLossUSD))
   {
      CloseBasket("BASKET STOP "+DoubleToString(p,2));
      return;
   }

   if(UseEquityDrawdownStop && g_startEquity>0)
   {
      double dd=(g_startEquity-AccountEquity())/g_startEquity*100.0;
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

   double lot=NextLot();
   if(lot<=0) return;
   OpenOrder(dir,lot);
}

void StartBasket()
{
   int dir=0;
   if(!TrendSignal(dir) || dir==0) return;
   if(CountPositions()>0) return;
   g_startEquity=AccountEquity();
   double lot=NormalizeLot(BaseLot);
   if(lot>0) OpenOrder(dir,lot);
}

void Log(string s)
{
   Print("[",BotName,"] ",s);
   if(!UseJournal) return;
   int h=FileOpen(JournalFile,FILE_READ|FILE_WRITE|FILE_CSV|FILE_SHARE_READ,';');
   if(h==INVALID_HANDLE) return;
   FileSeek(h,0,SEEK_END);
   FileWrite(h,TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),s,AccountBalance(),AccountEquity(),BasketProfit(),TotalLots(),CountPositions());
   FileClose(h);
}

void Dashboard()
{
   if(!ShowDashboard){Comment("");return;}
   int d=BasketDirection();
   string side=(d>0)?"BUY":(d<0)?"SELL":"NONE";
   double target=TargetPercentEquity ? AccountEquity()*BasketTargetPercent/100.0 : BasketTargetUSD;
   double marginPct=(AccountEquity()>0)?AccountFreeMargin()/AccountEquity()*100.0:0;
   string s="";
   s+="LOIC ADAPTIVE PYRAMID V2\n";
   s+="Symbol: "+Symbol()+" | TF: "+EnumToString(TrendTF)+"\n";
   s+="Basket: "+side+" | Pos: "+IntegerToString(CountPositions())+"/"+IntegerToString(MaxPositions)+"\n";
   s+="Lots: "+DoubleToString(TotalLots(),2)+"/"+DoubleToString(MaxTotalLots,2)+"\n";
   s+="P/L: $"+DoubleToString(BasketProfit(),2)+" | Target: $"+DoubleToString(target,2)+"\n";
   s+="Margin: "+DoubleToString(marginPct,0)+"% | Spread: "+DoubleToString((Ask-Bid)/Pip(),1)+" pips\n";
   s+="Mode: "+(IsDemo()?"DEMO":"LIVE")+" | LiveAllowed: "+(AllowLiveTrading?"YES":"NO");
   Comment(s);
}

int OnInit()
{
   if(AccountBalance()<=0) return INIT_FAILED;
   g_lastBar=iTime(Symbol(),TrendTF,0);
   g_startEquity=AccountEquity();
   Log("START | balance="+DoubleToString(AccountBalance(),2)+" | demo="+(IsDemo()?"YES":"NO"));
   return INIT_SUCCEEDED;
}

void OnTick()
{
   if(ShowDashboard) Dashboard();
   if(!TradingAllowed()) return;
   if(!SpreadOK() || !SessionOK()) return;

   int n=CountPositions();
   if(n>0)
      ManageBasket();
   else if(!AllowNewBasketOnlyOnNewBar || NewBar())
      StartBasket();
}
//+------------------------------------------------------------------+
