//+------------------------------------------------------------------+
//| mveuuh pro MT5.mq5                                         |
//| Trend + Structure + Quant Score + Adaptive Pyramiding            |
//| Multi-asset: Forex / Gold / Indices / Crypto                    |
//| V11: + BOSS FILTER (SAD/Sharp/AMA/Volume breakout confirmation)  |
//+------------------------------------------------------------------+
#property strict
#property version   "11.00"
#property description "mveuuh pro - multi-asset trend/structure/score EA with controlled multi-entry trading + Boss filter."

#include <Trade/Trade.mqh>
CTrade trade;

enum MarketProfile { AUTO_PROFILE=0, FOREX_PROFILE=1, GOLD_PROFILE=2, INDEX_PROFILE=3, CRYPTO_PROFILE=4 };

input string InpGeneral="=== GENERAL ===";
input string TradeComment="mveuuh 237";
input ulong MagicNumber=237;
input bool OnlyThisSymbol=true;
input bool AllowBuy=true;
input bool AllowSell=true;

input string InpMarket="=== ADAPTIVE MARKET PROFILE ===";
input MarketProfile Profile=AUTO_PROFILE;

double gSpreadMult=1.0,gATRMult=1.0,gLotMult=1.0,gMinScore=75.0;

input string InpPyramid="=== PYRAMID / MULTIPLE ENTRIES ===";
input int InitialPositions=2;
input int MaxPositions=8;
input string GridLotsStr="0.04,0.04,0.06,0.08,0.10,0.12,0.15,0.20";
input double MaxLotPerOrder=2.0;
input double MaxTotalLots=5.0;
input double MinEntryDistanceATR=0.60;
input int MinMinutesBetweenEntries=15;
input bool SameDirectionOnly=true;

input string InpTrend="=== MULTI-TIMEFRAME ANALYSIS ===";
input ENUM_TIMEFRAMES TrendTF=PERIOD_H1;
input ENUM_TIMEFRAMES StructureTF=PERIOD_M15;
input ENUM_TIMEFRAMES EntryTF=PERIOD_M5;
input int FastEMA=8;
input int MidEMA=21;
input int SlowEMA=50;
input int RSIPeriod=14;

input string InpQuant="=== QUANTITATIVE / QUALITY SCORE ===";
input bool UseQualityScore=true;
input double MinScore=75.0;
input double StrongScore=85.0;
input double BuyRSIMin=52.0;
input double BuyRSIMax=72.0;
input double SellRSIMin=28.0;
input double SellRSIMax=48.0;
input int ATRPeriod=14;
input double MinATRPercentOfPrice=0.01;
input double MinBodyATR=0.10;
input int StructureLookback=5;
input double MaxSpreadPips=80.0;

input string InpEntry="=== ENTRY DISCIPLINE ===";
input bool RequireTrendAlignment=true;
input bool RequireStructureBreak=true;
input bool RequirePullbackRejection=true;
input bool RequireRSI=true;
input bool RequireATR=true;

input string InpBoss="=== BOSS FILTER (SAD / SHARP / AMA / VOLUME) ===";
input bool UseBossFilter=true;        // adds up to +10 to the quality score when aligned
input bool RequireBossFilter=false;   // if true, blocks entries when the Boss filter disagrees
input int BossLookback=140;           // history depth used to rebuild SAD/AMA (min 100)

input string InpManage="=== BASKET MANAGEMENT ===";
input double BasketTP_USD=500.0;
input double BasketMaxLossUSD=500.0;
input bool UseBasketBE=true;
input double BE_StartPerPositionUSD=35.0;
input double BE_LockPerPositionUSD=10.0;
input bool UseTrailingBasket=true;
input double TrailStartUSD=100.0;
input double TrailGivebackUSD=40.0;

input string InpExec="=== EXECUTION ===";
input int SlippagePoints=30;
input bool UseATRStops=true;
input double SL_ATR_Mult=2.0;
input double TP_ATR_Mult=3.0;
input bool UseEquityProtection=true;
input double MaxEquityDrawdownPercent=20.0;

double GridLots[8];
int hFastTrend=INVALID_HANDLE,hMidTrend=INVALID_HANDLE,hSlowTrend=INVALID_HANDLE;
int hFastStruct=INVALID_HANDLE,hMidStruct=INVALID_HANDLE,hSlowStruct=INVALID_HANDLE;
int hFastEntry=INVALID_HANDLE,hMidEntry=INVALID_HANDLE,hSlowEntry=INVALID_HANDLE;
int hRSI=INVALID_HANDLE,hATR=INVALID_HANDLE;
datetime gLastEntryBar=0,gLastTradeTime=0;
double gBestBasketProfit=0.0,gCurrentScore=0.0;
int gLastDirection=0;

// Coefficients from the BOSS FINAL PACK indicator's SAD filter (66-tap weighted kernel)
double gBossCoef[66]={0.11859648,0.11781324,0.11548308,0.11166411,0.10645106,0.09997253,0.09238688,0.08387751,0.07464713,0.06491178,0.05489443,0.04481833,0.03490071,0.02534672,0.01634375,0.00805678,0.00062421,-0.00584512,-0.01127391,-0.01561738,-0.01886307,-0.02102974,-0.02216516,-0.02234315,-0.02165992,-0.02022973,-0.01818026,-0.01564777,-0.01277219,-0.00969230,-0.00654127,-0.00344276,-0.00050728,0.00217042,0.00451354,0.00646441,0.00798513,0.00905725,0.00968091,0.00987326,0.00966639,0.00910488,0.00824306,0.00714199,0.00586655,0.00448255,0.00305396,0.00164061,0.00029596,-0.00093445,-0.00201426,-0.00291701,-0.00362661,-0.00413703,-0.00445206,-0.00458437,-0.00455457,-0.00439006,-0.00412379,-0.00379323,-0.00343966,-0.00310850,-0.00285188,-0.00273508,-0.00274361,0.01018757};

double Pip(){ return (_Digits==3 || _Digits==5) ? _Point*10.0 : _Point; }

void ParseLots(){
 string parts[]; int n=StringSplit(GridLotsStr,',',parts);
 for(int i=0;i<8;i++) GridLots[i]=0.04;
 for(int i=0;i<n && i<8;i++) GridLots[i]=StringToDouble(parts[i]);
}

MarketProfile DetectProfile(){
 string s=_Symbol; StringToUpper(s);
 if(StringFind(s,"XAU")>=0 || StringFind(s,"GOLD")>=0 || StringFind(s,"XAG")>=0 || StringFind(s,"SILVER")>=0) return GOLD_PROFILE;
 if(StringFind(s,"BTC")>=0 || StringFind(s,"ETH")>=0 || StringFind(s,"XRP")>=0 || StringFind(s,"SOL")>=0 || StringFind(s,"DOGE")>=0 || StringFind(s,"ADA")>=0) return CRYPTO_PROFILE;
 if(StringFind(s,"NAS")>=0 || StringFind(s,"US100")>=0 || StringFind(s,"USTEC")>=0 || StringFind(s,"US30")>=0 || StringFind(s,"DJ")>=0 || StringFind(s,"SPX")>=0 || StringFind(s,"US500")>=0 || StringFind(s,"GER")>=0 || StringFind(s,"DE40")>=0 || StringFind(s,"DAX")>=0 || StringFind(s,"UK100")>=0 || StringFind(s,"FRA40")>=0) return INDEX_PROFILE;
 return FOREX_PROFILE;
}

void ConfigureProfile(){
 MarketProfile p=(Profile==AUTO_PROFILE ? DetectProfile() : Profile);
 gSpreadMult=1.0; gATRMult=1.0; gLotMult=1.0; gMinScore=MinScore;
 if(p==GOLD_PROFILE){ gSpreadMult=1.30; gATRMult=1.10; gLotMult=0.75; }
 else if(p==INDEX_PROFILE){ gSpreadMult=1.50; gATRMult=1.15; gLotMult=0.70; }
 else if(p==CRYPTO_PROFILE){ gSpreadMult=2.00; gATRMult=1.25; gLotMult=0.50; }
}

double NormalizeLot(double lot){
 double minLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN),maxLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX),step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
 if(step<=0) step=0.01; lot*=gLotMult; lot=MathMax(minLot,MathMin(maxLot,MathMin(lot,MaxLotPerOrder)));
 lot=MathFloor(lot/step+1e-9)*step; int digits=(step>=1.0?0:(step>=0.1?1:2)); return NormalizeDouble(lot,digits);
}

bool PositionMatches(int index){
 ulong ticket=PositionGetTicket(index); if(ticket==0 || !PositionSelectByTicket(ticket)) return false;
 if((ulong)PositionGetInteger(POSITION_MAGIC)!=MagicNumber) return false;
 if(OnlyThisSymbol && PositionGetString(POSITION_SYMBOL)!=_Symbol) return false;
 return true;
}
int CountPositions(){ int c=0; for(int i=PositionsTotal()-1;i>=0;i--) if(PositionMatches(i)) c++; return c; }
double TotalLots(){ double t=0; for(int i=PositionsTotal()-1;i>=0;i--) if(PositionMatches(i)) t+=PositionGetDouble(POSITION_VOLUME); return t; }
double BasketProfit(){ double p=0; for(int i=PositionsTotal()-1;i>=0;i--) if(PositionMatches(i)) p+=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP); return p; }

int BasketDirection(){
 int b=0,s=0; for(int i=PositionsTotal()-1;i>=0;i--){ if(!PositionMatches(i)) continue; ENUM_POSITION_TYPE t=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE); if(t==POSITION_TYPE_BUY)b++; if(t==POSITION_TYPE_SELL)s++; }
 if(b>0&&s==0)return 1; if(s>0&&b==0)return -1; return 0;
}

double LastEntryPrice(int direction){
 double price=0; datetime newest=0;
 for(int i=PositionsTotal()-1;i>=0;i--){ if(!PositionMatches(i))continue; ENUM_POSITION_TYPE t=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE); if((direction>0&&t!=POSITION_TYPE_BUY)||(direction<0&&t!=POSITION_TYPE_SELL))continue; datetime tm=(datetime)PositionGetInteger(POSITION_TIME); if(tm>=newest){newest=tm;price=PositionGetDouble(POSITION_PRICE_OPEN);} }
 return price;
}

bool SpreadOK(){ double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK),bid=SymbolInfoDouble(_Symbol,SYMBOL_BID); if(ask<=0||bid<=0)return false; return ((ask-bid)/Pip()<=MaxSpreadPips*gSpreadMult); }
bool NewEntryBar(){ datetime t=iTime(_Symbol,EntryTF,0); if(t<=0||t==gLastEntryBar)return false; gLastEntryBar=t; return true; }
bool CopyValue(int handle,double &v){ double a[1]; if(CopyBuffer(handle,0,1,1,a)!=1)return false; v=a[0]; return true; }
bool GetATR(double &atr){return CopyValue(hATR,atr);} bool GetRSI(double &rsi){return CopyValue(hRSI,rsi);}

bool GetRates(ENUM_TIMEFRAMES tf,MqlRates &r1,MqlRates &r2,MqlRates &r3){
 MqlRates r[4]; ArraySetAsSeries(r,true); if(CopyRates(_Symbol,tf,0,4,r)<4)return false; r1=r[1];r2=r[2];r3=r[3];return true;
}

bool TrendAligned(int direction,int hf,int hm,int hs){ double f,m,s; if(!CopyValue(hf,f)||!CopyValue(hm,m)||!CopyValue(hs,s))return false; return direction>0?(f>m&&m>s):(f<m&&m<s); }

bool StructureBreak(int direction){
 MqlRates r1,r2,r3; if(!GetRates(StructureTF,r1,r2,r3))return false; int n=MathMax(3,StructureLookback); MqlRates bars[]; ArraySetAsSeries(bars,true); if(CopyRates(_Symbol,StructureTF,2,n,bars)<n)return false;
 double hi=bars[0].high,lo=bars[0].low; for(int i=1;i<n;i++){hi=MathMax(hi,bars[i].high);lo=MathMin(lo,bars[i].low);} return direction>0?(r1.close>hi&&r1.close>r1.open):(r1.close<lo&&r1.close<r1.open);
}

bool PullbackRejection(int direction){
 MqlRates r1,r2,r3; if(!GetRates(EntryTF,r1,r2,r3))return false; double ema,atr; if(!CopyValue(hFastEntry,ema)||!GetATR(atr)||atr<=0)return false; if(MathAbs(r1.close-r1.open)<atr*MinBodyATR)return false;
 if(direction>0){bool reject=(r1.low<=ema&&r1.close>ema&&r1.close>r1.open);bool momentum=(r1.close>r2.high&&r1.close>r2.close);return reject||momentum;}
 bool reject=(r1.high>=ema&&r1.close<ema&&r1.close<r1.open);bool momentum=(r1.close<r2.low&&r1.close<r2.close);return reject||momentum;
}

bool RSIConfirm(int direction){ double rsi; if(!GetRSI(rsi))return false; return direction>0?(rsi>=BuyRSIMin&&rsi<=BuyRSIMax):(rsi>=SellRSIMin&&rsi<=SellRSIMax); }
bool ATRConfirm(){ double atr; if(!GetATR(atr))return false; double price=SymbolInfoDouble(_Symbol,SYMBOL_BID); if(price<=0)return false; return ((atr/price)*100.0>=MinATRPercentOfPrice*gATRMult); }

bool EnoughDistanceForAdd(int direction){ double atr; if(!GetATR(atr)||atr<=0)return false; double last=LastEntryPrice(direction); if(last<=0)return true; double price=direction>0?SymbolInfoDouble(_Symbol,SYMBOL_ASK):SymbolInfoDouble(_Symbol,SYMBOL_BID); return MathAbs(price-last)>=atr*MinEntryDistanceATR; }
bool TimeOKForAdd(){ return gLastTradeTime==0 || (TimeCurrent()-gLastTradeTime)>=MinMinutesBetweenEntries*60; }

//+------------------------------------------------------------------+
//| BOSS FILTER: SAD (66-tap weighted kernel) + Sharp (14-bar        |
//| regression) + AMA (Kaufman) + volume breakout, rebuilt from      |
//| scratch each call over a rolling window (no persistent buffers,  |
//| avoids the unindexed-array bug found in the original indicator). |
//+------------------------------------------------------------------+
bool BossConfirm(int direction){
 if(!UseBossFilter) return true; // filter disabled: never blocks, contributes no score elsewhere
 int n=MathMax(100,BossLookback);
 MqlRates r[]; ArraySetAsSeries(r,false);
 if(CopyRates(_Symbol,EntryTF,1,n,r)<n) return false; // not enough history yet

 double sadH[],sadL[],sharp[],ama[],ama_w[],volAvg[];
 ArrayResize(sadH,n); ArrayResize(sadL,n); ArrayResize(sharp,n);
 ArrayResize(ama,n);  ArrayResize(ama_w,n); ArrayResize(volAvg,n);

 for(int i=0;i<n;i++){
   double v=(double)r[i].tick_volume;
   volAvg[i]= (i>0) ? volAvg[i-1]+(2.0/51.0)*(v-volAvg[i-1]) : v;

   if(i>=13){
      int s=i-13; double mx=r[s].close,mn=r[s].close;
      for(int k=s;k<=i;k++){ if(r[k].close>mx) mx=r[k].close; if(r[k].close<mn) mn=r[k].close; }
      double fastE=2.0/3.0, slowE=2.0/31.0;
      double mltp=(mx!=mn) ? MathAbs(((r[i].close-mn)-(mx-r[i].close))/(mx-mn)) : 1.0;
      double ssc=mltp*(fastE-slowE)+slowE;
      if(i>0){ ama_w[i]=ama_w[i-1]+ssc*(r[i].close-ama_w[i-1]); ama[i]=ama[i-1]+ssc*(ama_w[i]-ama[i-1]); }
      else { ama_w[i]=ama[i]=r[i].close; }
      double sma=0; for(int k=0;k<14;k++) sma+=r[i-k].close; sma/=14.0;
      double slope=0; for(int k=0;k<14;k++) slope+=r[i-k].close*(14-(1.0+2.0*k))/2.0;
      sharp[i]=sma+6.0*slope/(15.0*14.0);
   } else {
      ama_w[i]=ama[i]=(i>0 ? ama[i-1] : r[i].close);
      sharp[i]=r[i].close;
   }

   if(i>=65){
      double sumH=0,sumL=0;
      for(int k=0;k<66;k++){
         double hlcc=(r[i-k].open+r[i-k].close+r[i-k].high+r[i-k].low)/4.0;
         sumH+=gBossCoef[k]*(hlcc+r[i-k].close)/2.0;
         sumL+=gBossCoef[k]*(hlcc+r[i-k].open)/2.0;
      }
      sadH[i]=sumH; sadL[i]=sumL;
   } else { sadH[i]=0; sadL[i]=0; }
 }

 int last=n-1;
 if(last<66) return false;
 bool volBreak=((double)r[last].tick_volume) > volAvg[last]*1.5;
 bool up = sadH[last]>sadL[last] && sharp[last]>sharp[last-1] && ama[last]>ama[last-1] && volBreak;
 bool dn = sadH[last]<sadL[last] && sharp[last]<sharp[last-1] && ama[last]<ama[last-1] && volBreak;
 return direction>0 ? up : dn;
}

// 100-point transparent quality score. This is a deterministic quantitative filter;
// it is intentionally not presented as a trained ML model.
double QualityScore(int direction){
 double score=0;
 if(TrendAligned(direction,hFastTrend,hMidTrend,hSlowTrend))score+=15;
 if(TrendAligned(direction,hFastStruct,hMidStruct,hSlowStruct))score+=12;
 if(TrendAligned(direction,hFastEntry,hMidEntry,hSlowEntry))score+=8;
 if(StructureBreak(direction))score+=15;
 if(PullbackRejection(direction))score+=10;
 if(RSIConfirm(direction))score+=10;
 if(ATRConfirm())score+=10;
 MqlRates r1,r2,r3;double atr; if(GetRates(EntryTF,r1,r2,r3)&&GetATR(atr)&&atr>0){if((direction>0?r1.close>r1.open:r1.close<r1.open)&&MathAbs(r1.close-r1.open)>=atr*0.25)score+=5;}
 if(SpreadOK())score+=5;
 if(UseBossFilter && BossConfirm(direction))score+=10;
 return score;
}

bool Signal(int direction,double &score){
 if(!SpreadOK())return false; score=QualityScore(direction); gCurrentScore=score;
 if(RequireTrendAlignment && (!TrendAligned(direction,hFastTrend,hMidTrend,hSlowTrend)||!TrendAligned(direction,hFastStruct,hMidStruct,hSlowStruct)))return false;
 if(RequireStructureBreak&&!StructureBreak(direction))return false;
 if(RequirePullbackRejection&&!PullbackRejection(direction))return false;
 if(RequireRSI&&!RSIConfirm(direction))return false;
 if(RequireATR&&!ATRConfirm())return false;
 if(RequireBossFilter && UseBossFilter && !BossConfirm(direction))return false;
 if(UseQualityScore&&score<gMinScore)return false;
 return true;
}

void CloseBasket(string reason){
 double before=BasketProfit(); for(int pass=0;pass<2;pass++)for(int i=PositionsTotal()-1;i>=0;i--){if(!PositionMatches(i))continue;ulong ticket=PositionGetTicket(i);trade.PositionClose(ticket,(ulong)SlippagePoints);} gBestBasketProfit=0;gLastDirection=0;Print("BASKET CLOSED: ",reason," profit=",DoubleToString(before,2));
}

bool OpenOne(int direction,double lot,int index){
   lot=NormalizeLot(lot);
   if(lot<=0 || TotalLots()+lot>MaxTotalLots) return false;
   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double price=(direction>0?ask:bid);
   if(price<=0) return false;

   double sl=0,tp=0,atr=0;
   if(UseATRStops && GetATR(atr) && atr>0){
      if(direction>0){ sl=price-atr*SL_ATR_Mult; tp=price+atr*TP_ATR_Mult; }
      else { sl=price+atr*SL_ATR_Mult; tp=price-atr*TP_ATR_Mult; }
      int stops=(int)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);
      double minDist=stops*_Point;
      if(minDist>0){
         if(direction>0){ if(price-sl<minDist) sl=price-minDist; if(tp-price<minDist) tp=price+minDist; }
         else { if(sl-price<minDist) sl=price+minDist; if(price-tp<minDist) tp=price-minDist; }
      }
      sl=NormalizeDouble(sl,_Digits); tp=NormalizeDouble(tp,_Digits);
   }

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(SlippagePoints);
   string side=direction>0?"BUY":"SELL";
   string comment=TradeComment+" "+side+" #"+IntegerToString(index);
   bool ok=direction>0 ? trade.Buy(lot,_Symbol,0,sl,tp,comment)
                       : trade.Sell(lot,_Symbol,0,sl,tp,comment);
   if(!ok) Print("Order failed #",index," ",trade.ResultRetcodeDescription());
   else { gLastTradeTime=TimeCurrent(); gLastDirection=direction; }
   return ok;
}

void OpenInitialBasket(int direction){
 if(CountPositions()>0||!SpreadOK())return;int qty=MathMax(1,MathMin(InitialPositions,8)),opened=0;for(int i=0;i<qty;i++){if(OpenOne(direction,GridLots[i],i+1))opened++;Sleep(120);}if(opened>0)Print("INITIAL BASKET: ",direction>0?"BUY":"SELL"," positions=",opened," score=",DoubleToString(gCurrentScore,1)," symbol=",_Symbol);
}

void TryPyramid(){
 int cnt=CountPositions();if(cnt<=0||cnt>=MathMin(MaxPositions,8)||!TimeOKForAdd()||!SpreadOK())return;int dir=BasketDirection();if(dir==0)return;if(SameDirectionOnly&&dir!=gLastDirection&&gLastDirection!=0)return;double score=0;if(!Signal(dir,score))return;if(UseQualityScore&&score<StrongScore)return;if(!EnoughDistanceForAdd(dir))return;int idx=cnt;if(idx>=8)return;if(OpenOne(dir,GridLots[idx],idx+1))Print("PYRAMID ADD: ",dir>0?"BUY":"SELL"," #",idx+1," score=",DoubleToString(score,1)," positions=",CountPositions());
}

void ManageBasket(){
 int cnt=CountPositions();if(cnt<=0)return;double profit=BasketProfit();if(profit>=BasketTP_USD){CloseBasket("BASKET TP");return;}if(profit<=-MathAbs(BasketMaxLossUSD)){CloseBasket("BASKET MAX LOSS");return;}if(profit>gBestBasketProfit)gBestBasketProfit=profit;
 if(UseBasketBE){double start=BE_StartPerPositionUSD*cnt,lock=BE_LockPerPositionUSD*cnt;if(gBestBasketProfit>=start&&profit<=lock){CloseBasket("BASKET BE LOCK");return;}}
 if(UseTrailingBasket&&gBestBasketProfit>=TrailStartUSD&&profit<=gBestBasketProfit-TrailGivebackUSD){CloseBasket("BASKET TRAILING");return;}
}

double EquityDrawdownPercent(){
   double bal=AccountInfoDouble(ACCOUNT_BALANCE);
   double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   if(bal<=0) return 0;
   return (bal-eq)/bal*100.0;
}
void CheckEquityProtection(){
   if(!UseEquityProtection) return;
   if(EquityDrawdownPercent()>=MaxEquityDrawdownPercent && CountPositions()>0)
      CloseBasket("EQUITY PROTECTION");
}

int OnInit(){
 ParseLots();ConfigureProfile();
 hFastTrend=iMA(_Symbol,TrendTF,FastEMA,0,MODE_EMA,PRICE_CLOSE);hMidTrend=iMA(_Symbol,TrendTF,MidEMA,0,MODE_EMA,PRICE_CLOSE);hSlowTrend=iMA(_Symbol,TrendTF,SlowEMA,0,MODE_EMA,PRICE_CLOSE);
 hFastStruct=iMA(_Symbol,StructureTF,FastEMA,0,MODE_EMA,PRICE_CLOSE);hMidStruct=iMA(_Symbol,StructureTF,MidEMA,0,MODE_EMA,PRICE_CLOSE);hSlowStruct=iMA(_Symbol,StructureTF,SlowEMA,0,MODE_EMA,PRICE_CLOSE);
 hFastEntry=iMA(_Symbol,EntryTF,FastEMA,0,MODE_EMA,PRICE_CLOSE);hMidEntry=iMA(_Symbol,EntryTF,MidEMA,0,MODE_EMA,PRICE_CLOSE);hSlowEntry=iMA(_Symbol,EntryTF,SlowEMA,0,MODE_EMA,PRICE_CLOSE);
 hRSI=iRSI(_Symbol,EntryTF,RSIPeriod,PRICE_CLOSE);hATR=iATR(_Symbol,EntryTF,ATRPeriod);
 if(hFastTrend==INVALID_HANDLE||hMidTrend==INVALID_HANDLE||hSlowTrend==INVALID_HANDLE||hFastStruct==INVALID_HANDLE||hMidStruct==INVALID_HANDLE||hSlowStruct==INVALID_HANDLE||hFastEntry==INVALID_HANDLE||hMidEntry==INVALID_HANDLE||hSlowEntry==INVALID_HANDLE||hRSI==INVALID_HANDLE||hATR==INVALID_HANDLE)return INIT_FAILED;
 if(BossLookback<100) Print("BOSS FILTER: BossLookback<100, clamped to 100 internally.");
 Print("mveuuh pro V11 initialized on ",_Symbol," (Boss filter: ",(UseBossFilter?"ON":"OFF"),", required: ",(RequireBossFilter?"YES":"NO"),")");return INIT_SUCCEEDED;
}

void OnDeinit(const int reason){
 if(hFastTrend!=INVALID_HANDLE)IndicatorRelease(hFastTrend);if(hMidTrend!=INVALID_HANDLE)IndicatorRelease(hMidTrend);if(hSlowTrend!=INVALID_HANDLE)IndicatorRelease(hSlowTrend);if(hFastStruct!=INVALID_HANDLE)IndicatorRelease(hFastStruct);if(hMidStruct!=INVALID_HANDLE)IndicatorRelease(hMidStruct);if(hSlowStruct!=INVALID_HANDLE)IndicatorRelease(hSlowStruct);if(hFastEntry!=INVALID_HANDLE)IndicatorRelease(hFastEntry);if(hMidEntry!=INVALID_HANDLE)IndicatorRelease(hMidEntry);if(hSlowEntry!=INVALID_HANDLE)IndicatorRelease(hSlowEntry);if(hRSI!=INVALID_HANDLE)IndicatorRelease(hRSI);if(hATR!=INVALID_HANDLE)IndicatorRelease(hATR);
 Print("mveuuh pro V11 deinitialized successfully.");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick(){
   // 1. Protection globale du capital en premier
   CheckEquityProtection();

   // 2. Gestion du panier actif (TP, Stop Loss, Break-Even, Trailing)
   if(CountPositions() > 0){
      ManageBasket();
      // Si des positions sont ouvertes, on cherche a renforcer (Pyramiding) sur une nouvelle barre d'entree
      if(CountPositions() > 0 && NewEntryBar()){
         TryPyramid();
      }
      return; // Si on a deja des positions, on ne cherche pas a ouvrir un nouveau panier initial
   }

   // 3. Pas de position ouverte : recherche d'un nouveau signal pour lancer un panier initial
   if(!NewEntryBar() || !SpreadOK()) return;

   // Les deux sens sont evalues avant toute decision, pour detecter un conflit BUY/SELL simultane
   // (garde-fou volontaire : en cas de conflit, on ne trade pas plutot que de choisir arbitrairement)
   double buyScore=0,sellScore=0;
   bool buySignal = AllowBuy && Signal(1,buyScore);
   bool sellSignal = AllowSell && Signal(-1,sellScore);

   if(buySignal && !sellSignal){
      gCurrentScore=buyScore;
      OpenInitialBasket(1);
   }
   else if(sellSignal && !buySignal){
      gCurrentScore=sellScore;
      OpenInitialBasket(-1);
   }
   else if(buySignal && sellSignal){
      Print("SIGNAL CONFLICT: BUY=",DoubleToString(buyScore,1)," SELL=",DoubleToString(sellScore,1)," -> no trade.");
   }
}
//+------------------------------------------------------------------+
