#property strict
#property version "0.919"
#define OnInit OnInit_Core
#define OnDeinit OnDeinit_Core
#define OnTick OnTick_Core
#define UpdateDisplay UpdateDisplay_Core
#define TrailSellStops TrailSellStops_Core
#include "EAGOLD_CORE_0918.mq4"
#undef OnInit
#undef OnDeinit
#undef OnTick
#undef UpdateDisplay
#undef TrailSellStops
void TrailSellStops(){for(int i=OrdersTotal()-1;i>=0;i--){if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;if(!IsEAGOLDOrder()||OrderType()!=OP_SELLSTOP) continue;RefreshRates();bool startup=(CountOpenSide(OP_BUY)==0&&CountOpenSide(OP_SELL)==0);double desired=startup?GetSellStartupTrailTarget():NormalizePrice(Bid-PointsToPrice(SmartGrid1));double current=OrderOpenPrice();double trail=PointsToPrice(PendingStepTrail);double stopLevel=MarketInfo(Symbol(),MODE_STOPLEVEL)*Point;if(desired<=current) continue;if((desired-current)<trail) continue;if(!startup&&desired>=Bid-stopLevel) continue;ResetLastError();if(!OrderModify(OrderTicket(),desired,0,0,0,clrNONE)) Print(EA_NAME," SELLSTOP trail failed ticket=",OrderTicket()," error=",GetLastError());else Print(EA_NAME," SELLSTOP moved TOWARD price ticket=",OrderTicket()," from=",DoubleToString(current,Digits)," to=",DoubleToString(desired,Digits)," trail=",DoubleToString(PendingStepTrail,0)," startup=",startup);}}
void UpdateDisplay(){string text=EA_NAME+" v0.919";text+="\nBUY="+IntegerToString(CountOpenSide(OP_BUY));text+=" SELL="+IntegerToString(CountOpenSide(OP_SELL));text+="\nMiniGrid1="+DoubleToString(MiniGrid1,Digits);text+=" SmartGrid1="+DoubleToString(SmartGrid1,Digits);text+="\nMiniGrid2="+DoubleToString(MiniGrid2,Digits);text+=" SmartGrid2="+DoubleToString(SmartGrid2,Digits);Comment(text);}
int OnInit(){SyncBuyExecutionState();Print(EA_NAME," v0.919 initialized. FirstStep=",DoubleToString(FirstStep,0)," PendingStepTrail=",DoubleToString(PendingStepTrail,0));EnsureInitialPendings();UpdateDisplay();return(INIT_SUCCEEDED);}
void OnDeinit(const int reason){Comment("");}
void OnTick(){RefreshRates();EnsureInitialPendings();TrailBuyStops();TrailSellStops();ProcessBuyTakeProfit();EnsureNextBuyStop();EnsureNextSellStop();ProcessSellProfit();ProcessCloseBy();UpdateDisplay();}
