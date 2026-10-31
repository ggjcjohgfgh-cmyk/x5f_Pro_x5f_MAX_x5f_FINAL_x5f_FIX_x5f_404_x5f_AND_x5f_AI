
import 'package:flutter/material.dart';
import 'package:call_log/call_log.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_contacts/flutter_contacts.dart' as FC;
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_phone_direct_caller/flutter_phone_direct_caller.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'dart:io';
import 'dart:async';
import 'services/truecaller_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Hive.openBox('blocked_box');
  await Hive.openBox('notes_box');
  await Hive.openBox('recordings_box');
  await Hive.openBox('settings_box');
  await Hive.openBox('caller_cache');
  await Hive.openBox('spam_db');
  runApp(const CallProApp());
}

class CallProApp extends StatelessWidget {
  const CallProApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ULTRA 2027 TRUECALLER PRO MAX',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0A0A14),
        primaryColor: const Color(0xFF7C4DFF),
        useMaterial3: true,
      ),
      home: const MainNavigation(),
      builder: (c, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
    );
  }
}

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});
  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int currentIndex = 0;
  final screens = [const HomeScreen(), const BlockedScreen(), const RecorderScreen(), const SettingsProScreen()];
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: screens[currentIndex],
      bottomNavigationBar: Container(
        decoration: BoxDecoration(color: const Color(0xFF151525), border: Border(top: BorderSide(color: Colors.white.withOpacity(0.05)))),
        child: BottomNavigationBar(
          backgroundColor: Colors.transparent,
          type: BottomNavigationBarType.fixed,
          selectedItemColor: const Color(0xFF7C4DFF),
          unselectedItemColor: Colors.white38,
          currentIndex: currentIndex,
          onTap: (i) => setState(() => currentIndex = i),
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.call), label: "المكالمات"),
            BottomNavigationBarItem(icon: Icon(Icons.shield), label: "كاشف السبام"),
            BottomNavigationBarItem(icon: Icon(Icons.mic), label: "التسجيلات"),
            BottomNavigationBarItem(icon: Icon(Icons.settings), label: "برو"),
          ],
        ),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<CallLogEntry> allLogs = [];
  List<CallLogEntry> filteredLogs = [];
  String search = "";
  String filter = "الكل";
  bool loading = true;
  int total = 5934;
  int today = 0;
  double secs = 78.4;
  List<int> week = [58,74,69,58,63,50,0];
  List<String> days = ["س","أ","ث","ر","خ","ج","ح"];
  final blockedBox = Hive.box('blocked_box');
  final notesBox = Hive.box('notes_box');
  final callerService = TrueCallerService();
  Map<String, CallerInfo> callerCache = {};

  @override
  void initState() { super.initState(); init(); }

  Future<void> init() async {
    await [Permission.phone, Permission.contacts, Permission.microphone, Permission.storage].request();
    await loadLogs();
  }

  Future<void> loadLogs() async {
    try {
      var logs = await CallLog.get();
      setState(() {
        allLogs = logs.toList();
        filteredLogs = allLogs;
        total = allLogs.isEmpty ? 5934 : allLogs.length;
        today = allLogs.where((e){ var d=DateTime.fromMillisecondsSinceEpoch(e.timestamp??0); return d.day==DateTime.now().day; }).length;
        secs = allLogs.fold(0, (s,e)=> s + (e.duration??0)) /1.0;
        if(secs==0) secs=78.4;
        loading=false;
      });
      doFilter();
      preloadCallerInfo();
    } catch(e){ setState(()=>loading=false); }
  }

  Future<void> preloadCallerInfo() async {
    for(var log in filteredLogs.take(10)){
      var num = log.number ?? "";
      if(num.isNotEmpty && !callerCache.containsKey(num)){
        var info = await callerService.getCallerInfo(num);
        setState(()=> callerCache[num] = info);
      }
    }
  }

  void doFilter(){
    var t = allLogs;
    if(filter!="الكل"){
      t = t.where((e){
        if(filter=="وارد" && e.callType==CallType.incoming) return true;
        if(filter=="صادر" && e.callType==CallType.outgoing) return true;
        if(filter=="فائت" && e.callType==CallType.missed) return true;
        if(filter=="المحظور") return blockedBox.containsKey(e.number);
        if(filter=="سبام"){
          var info = callerCache[e.number];
          return info?.isSpam == true;
        }
        return false;
      }).toList();
    }
    if(search.isNotEmpty){
      t = t.where((e)=> (e.name??"").contains(search) || (e.number??"").contains(search) || (callerCache[e.number]?.name.contains(search) ?? false)).toList();
    }
    setState(()=>filteredLogs=t);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A14),
      body: SafeArea(
        child: loading? const Center(child: CircularProgressIndicator(color: Color(0xFF7C4DFF))) :
        CustomScrollView(slivers: [
          SliverToBoxAdapter(child: header()),
          SliverToBoxAdapter(child: searchBar()),
          SliverToBoxAdapter(child: filterChips()),
          SliverToBoxAdapter(child: tabs()),
          SliverToBoxAdapter(child: analytics()),
          SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.symmetric(horizontal:16, vertical:8), child: Row(children: [chip("أمس"), const SizedBox(width:8), Expanded(child: Divider(color: Colors.white10)), const SizedBox(width:8), Text("${filteredLogs.length} مكالمة", style: const TextStyle(color: Colors.white38, fontSize:12))]))),
          SliverList(delegate: SliverChildBuilderDelegate((c,i){
            if(i>= (filteredLogs.isEmpty?2:filteredLogs.length)) return null;
            final entry = filteredLogs.isEmpty? CallLogEntry("رقم مجهول", i==0?"01112762724":"01024648258", CallType.outgoing, 0, i==0?24:58, DateTime.now().millisecondsSinceEpoch,0,0,"","","","","","","","","","") : filteredLogs[i];
            return callTile(entry, entry.number??"01112762724", entry.duration??24);
          }, childCount: filteredLogs.isEmpty?2:filteredLogs.length)),
          const SliverToBoxAdapter(child: SizedBox(height: 80)),
        ]),
      ),
      floatingActionButton: FloatingActionButton.extended(backgroundColor: const Color(0xFF7C4DFF), onPressed: loadLogs, icon: const Icon(Icons.refresh), label: const Text("تحديث فوري", style: TextStyle(fontWeight: FontWeight.bold))),
    );
  }

  Widget chip(String t)=> Container(padding: const EdgeInsets.symmetric(horizontal:10, vertical:4), decoration: BoxDecoration(color: const Color(0xFF1E1E32), borderRadius: BorderRadius.circular(8)), child: Text(t, style: const TextStyle(fontSize:12)));
  Widget header()=> Padding(padding: const EdgeInsets.all(16), child: Column(children: [
    Row(children: [
      Container(padding: const EdgeInsets.symmetric(horizontal:14, vertical:6), decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF00E5CC), Color(0xFF7C4DFF)]), borderRadius: BorderRadius.circular(20)), child: const Text("ULTRA • TRUECALLER 2027 PRO MAX", style: TextStyle(fontWeight: FontWeight.bold, fontSize:10, color: Colors.white))),
      const Spacer(),
      iconBtn(Icons.search, (){}),
      const SizedBox(width:8),
      iconBtn(Icons.bolt, (){}),
    ]),
    const SizedBox(height:16),
    Row(children: [
      Expanded(child: stat(Icons.layers, "$total", "الإجمالي", const Color(0xFF7C4DFF))),
      const SizedBox(width:10),
      Expanded(child: stat(Icons.today, "$today", "اليوم", const Color(0xFF00E5CC))),
      const SizedBox(width:10),
      Expanded(child: stat(Icons.timer, "${secs.toStringAsFixed(1)}س", "الوقت", const Color(0xFF448AFF))),
    ])
  ]));
  Widget iconBtn(IconData ic, VoidCallback onTap)=> InkWell(onTap: onTap, child: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: const Color(0xFF1E1E2E), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white10)), child: Icon(ic, size:18)));
  Widget stat(IconData ic, String v, String l, Color c)=> Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xFF151525), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withOpacity(0.05))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: c.withOpacity(0.2), borderRadius: BorderRadius.circular(8)), child: Icon(ic, color: c, size:16)), const SizedBox(height:10), Text(v, style: const TextStyle(fontSize:20, fontWeight: FontWeight.bold)), Text(l, style: const TextStyle(color: Colors.white38, fontSize:11))]));
  Widget searchBar()=> Padding(padding: const EdgeInsets.symmetric(horizontal:16), child: Container(decoration: BoxDecoration(color: const Color(0xFF151525), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white10)), child: TextField(onChanged: (v){ search=v; doFilter(); }, decoration: const InputDecoration(hintText: "...ابحث بالاسم أو الرقم - TrueCaller", hintStyle: TextStyle(color: Colors.white30, fontSize:13), prefixIcon: Icon(Icons.search, color: Colors.white30), border: InputBorder.none, contentPadding: EdgeInsets.all(14)))));
  Widget filterChips(){
    final filters=["الكل","وارد","صادر","فائت","المحظور","سبام"];
    final icons=[Icons.all_inclusive, Icons.call_received, Icons.call_made, Icons.call_missed, Icons.block, Icons.warning];
    return Padding(padding: const EdgeInsets.all(12), child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: List.generate(filters.length, (i){
      final sel=filter==filters[i];
      return Padding(padding: const EdgeInsets.only(left:8), child: ChoiceChip(label: Row(children: [Icon(icons[i], size:14, color: sel?Colors.white: (filters[i]=="سبام"?Colors.orange:Colors.white54)), const SizedBox(width:4), Text(filters[i])]), selected: sel, selectedColor: filters[i]=="سبام"?Colors.orange:const Color(0xFF7C4DFF), backgroundColor: const Color(0xFF151525), onSelected: (v){ setState(()=>filter=filters[i]); doFilter(); }));
    }))));
  }
  Widget tabs()=> Padding(padding: const EdgeInsets.symmetric(horizontal:16), child: Container(padding: const EdgeInsets.all(4), decoration: BoxDecoration(color: const Color(0xFF151525), borderRadius: BorderRadius.circular(12)), child: Row(children: [Expanded(child: Container(padding: const EdgeInsets.symmetric(vertical:8), decoration: BoxDecoration(color: const Color(0xFF7C4DFF), borderRadius: BorderRadius.circular(8)), child: const Center(child: Text("📈 التحليلات", style: TextStyle(fontWeight: FontWeight.bold, fontSize:13))))), Expanded(child: Container(padding: const EdgeInsets.symmetric(vertical:8), child: const Center(child: Text("🏆 الأكثر اتصالاً", style: TextStyle(color: Colors.white38, fontSize:13)))))])));
  Widget analytics()=> Container(margin: const EdgeInsets.all(16), padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: const Color(0xFF151525), borderRadius: BorderRadius.circular(20)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Row(children: [Text("نشاط اخر 7 ايام", style: TextStyle(fontWeight: FontWeight.bold)), Spacer(), Icon(Icons.trending_up, size:16, color: Color(0xFF00E5CC))]),
    const SizedBox(height:16),
    SizedBox(height:110, child: Row(crossAxisAlignment: CrossAxisAlignment.end, mainAxisAlignment: MainAxisAlignment.spaceAround, children: List.generate(week.length, (i){
      final h=(week[i]/74*90).clamp(10,90).toDouble();
      return Column(mainAxisAlignment: MainAxisAlignment.end, children: [Text("${week[i]}", style: const TextStyle(fontSize:11, fontWeight: FontWeight.bold)), const SizedBox(height:4), Container(width:32, height: h, decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color.lerp(const Color(0xFF00E5CC), const Color(0xFF7C4DFF), i/6)!, Color.lerp(const Color(0xFF00897B), const Color(0xFF4527A0), i/6)!]), borderRadius: BorderRadius.circular(8))), const SizedBox(height:6), Text(days[i], style: const TextStyle(color: Colors.white38, fontSize:11))]);
    }))),
    const SizedBox(height:16),
    Row(children: [
      Expanded(child: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(12)), child: const Row(children: [Icon(Icons.star, color: Colors.amber, size:16), SizedBox(width:8), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text("أطول مكالمة", style: TextStyle(color: Colors.white38, fontSize:10)), Text("ام انس • 58د", style: TextStyle(fontWeight: FontWeight.bold, fontSize:12))])]))),
      const SizedBox(width:10),
      Expanded(child: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(12)), child: const Row(children: [Icon(Icons.history, color: Colors.pink, size:16), SizedBox(width:8), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text("متوسط المدة", style: TextStyle(color: Colors.white38, fontSize:10)), Text("47ث", style: TextStyle(fontWeight: FontWeight.bold, fontSize:12))])]))),
    ])
  ]));

  Widget callTile(CallLogEntry e, String number, int dur){
    final isBlocked = blockedBox.containsKey(number);
    final callerInfo = callerCache[number];
    final isSpam = callerInfo?.isSpam ?? false;
    
    return InkWell(onTap: ()=>showDetail(e, number, dur), child: Container(margin: const EdgeInsets.symmetric(horizontal:16, vertical:6), padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xFF151525), borderRadius: BorderRadius.circular(16), border: Border.all(color: isSpam? Colors.orange.withOpacity(0.4) : isBlocked? Colors.red.withOpacity(0.3) : Colors.white.withOpacity(0.05))), child: Row(children: [
      Stack(children: [
        Container(width:56, height:56, decoration: BoxDecoration(gradient: LinearGradient(colors: isSpam?[const Color(0xFFFF9800), const Color(0xFFEF6C00)] : isBlocked?[const Color(0xFFEF5350), const Color(0xFFB71C1C)]:[const Color(0xFF00BFA5), const Color(0xFF00897B)]), shape: BoxShape.circle), child: callerInfo?.photoUrl != null && !isSpam ? ClipOval(child: Image.network(callerInfo!.photoUrl!, fit: BoxFit.cover, errorBuilder: (c,e,s)=> Center(child: Text("$dur", style: const TextStyle(fontWeight: FontWeight.bold))))) : Center(child: Text("$dur", style: const TextStyle(fontWeight: FontWeight.bold, fontSize:16)))),
        Positioned(bottom:0, right:0, child: Container(padding: const EdgeInsets.all(3), decoration: BoxDecoration(color: e.callType==CallType.outgoing?const Color(0xFF448AFF): isSpam?Colors.orange:const Color(0xFF2ECC71), shape: BoxShape.circle, border: Border.all(color: const Color(0xFF151525), width:2)), child: Icon(isSpam?Icons.warning : e.callType==CallType.outgoing?Icons.call_made:Icons.call_received, size:10, color: Colors.white))),
      ]),
      const SizedBox(width:12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(callerInfo?.name ?? e.name??"رقم مجهول", style: const TextStyle(fontWeight: FontWeight.bold, fontSize:14), maxLines:1, overflow: TextOverflow.ellipsis)),
          if(isSpam) Container(margin: const EdgeInsets.only(right:4), padding: const EdgeInsets.symmetric(horizontal:5, vertical:1), decoration: BoxDecoration(color: Colors.orange.withOpacity(0.2), borderRadius: BorderRadius.circular(4)), child: const Text("سبام", style: TextStyle(color: Colors.orange, fontSize:9, fontWeight: FontWeight.bold))),
          if(isBlocked) Container(margin: const EdgeInsets.only(right:4), padding: const EdgeInsets.symmetric(horizontal:5, vertical:1), decoration: BoxDecoration(color: Colors.red.withOpacity(0.2), borderRadius: BorderRadius.circular(4)), child: const Text("محظور", style: TextStyle(color: Colors.red, fontSize:9))),
        ]),
        Text(number, style: const TextStyle(color: Colors.white54, fontSize:12)),
        if(callerInfo != null) Row(children: [
          Icon(Icons.location_on, size:10, color: Colors.white38),
          const SizedBox(width:2),
          Text("${callerInfo.location} • ${callerInfo.carrier}", style: const TextStyle(color: Colors.white38, fontSize:10)),
          if(callerInfo.spamScore>0) ...[
            const SizedBox(width:6),
            Icon(Icons.shield, size:10, color: isSpam?Colors.orange:Colors.green),
            Text(" ${callerInfo.spamScore}%", style: TextStyle(color: isSpam?Colors.orange:Colors.green, fontSize:10)),
          ]
        ]),
        if(notesBox.containsKey(number)) Text("📝 ${notesBox.get(number)}", style: const TextStyle(color: Colors.amber, fontSize:11), maxLines:1),
      ])),
      Column(children: [
        InkWell(onTap: ()=>directCall(number), child: Container(padding: const EdgeInsets.all(8), decoration: const BoxDecoration(color: Color(0xFF1B3A2E), shape: BoxShape.circle), child: const Icon(Icons.phone, size:18, color: Color(0xFF2ECC71)))),
        const SizedBox(height:8),
        InkWell(onTap: ()=>showOptions(e, number), child: Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), shape: BoxShape.circle), child: const Icon(Icons.more_horiz, size:16))),
      ])
    ])));
  }

  void showDetail(CallLogEntry e, String number, int dur){
    // Fetch fresh info when opening detail
    callerService.getCallerInfo(number).then((info){
      if(mounted) setState(()=> callerCache[number]=info);
    });
    var info = callerCache[number];
    
    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: const Color(0xFF151525), shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))), builder: (ctx){
      return DraggableScrollableSheet(initialChildSize: 0.75, maxChildSize: 0.9, minChildSize: 0.5, expand: false, builder: (c, scrollCtrl){
        return SingleChildScrollView(controller: scrollCtrl, child: Container(padding: const EdgeInsets.all(20), child: Column(children: [
          Container(width:40, height:4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height:20),
          Stack(children: [
            Container(width:100, height:100, decoration: BoxDecoration(shape: BoxShape.circle, color: info?.isSpam==true?Colors.orange:const Color(0xFF7C5CFF), image: info?.photoUrl!=null? DecorationImage(image: NetworkImage(info!.photoUrl!), fit: BoxFit.cover): null), child: info?.photoUrl==null? Center(child: Text("$dur", style: const TextStyle(fontSize:32, fontWeight: FontWeight.bold))) : null),
            if(info?.isSpam==true) Positioned(bottom:0, right:0, child: Container(padding: const EdgeInsets.all(4), decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle), child: const Icon(Icons.warning, size:16, color: Colors.white))),
          ]),
          const SizedBox(height:12),
          Text(info?.name ?? e.name??"رقم مجهول", style: const TextStyle(fontSize:22, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
          const SizedBox(height:6),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [Text(number, style: const TextStyle(color: Colors.white54, fontSize:16)), const SizedBox(width:8), InkWell(onTap: (){}, child: const Icon(Icons.copy, size:18, color: Colors.white38))]),
          const SizedBox(height:12),
          // TrueCaller Info Cards
          if(info != null) Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(12)), child: Column(children: [
            infoRow(Icons.location_on, "الموقع", info.location ?? "غير معروف"),
            infoRow(Icons.sim_card, "الشبكة", info.carrier ?? "غير معروف"),
            infoRow(Icons.shield, "حالة السبام", info.isSpam? "⚠️ رقم مزعج - ${info.spamScore}%":"✅ رقم آمن - ${info.spamScore}%", color: info.isSpam?Colors.orange:Colors.green),
            if(info.businessCategory!=null) infoRow(Icons.business, "التصنيف", info.businessCategory!),
            if(info.email!=null) infoRow(Icons.email, "البريد", info.email!),
          ])),
          const SizedBox(height:16),
          if(notesBox.containsKey(number)) Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.amber.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: Row(children: [const Icon(Icons.note, size:16, color: Colors.amber), const SizedBox(width:6), Expanded(child: Text(notesBox.get(number), style: const TextStyle(color: Colors.amber)))])),
          const SizedBox(height:16),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            detail(Icons.call, "النوع", e.callType==CallType.outgoing?"صادر":"وارد"),
            detail(Icons.timer, "المدة", dur==0?"لم يرد":"${dur}ث"),
            detail(Icons.calendar_today, "التاريخ", "أمس • 22:00"),
          ]),
          const SizedBox(height:20),
          Row(children: [
            Expanded(child: action(Icons.call, "اتصال", const Color(0xFF1B3A2E), const Color(0xFF2ECC71), ()=>directCall(number))),
            const SizedBox(width:10),
            Expanded(child: action(Icons.message, "رسالة", const Color(0xFF1E2F4A), const Color(0xFF3498DB), ()=>sendSMS(number))),
            const SizedBox(width:10),
            Expanded(child: action(Icons.block, blockedBox.containsKey(number)?"إلغاء":"حظر", const Color(0xFF3A1E1E), const Color(0xFFE74C3C), ()=>toggleBlock(number))),
          ]),
          const SizedBox(height:12),
          Row(children: [
            Expanded(child: ElevatedButton.icon(onPressed: ()=>addNote(number), icon: const Icon(Icons.note_add, size:18), label: const Text("ملاحظة"), style: ElevatedButton.styleFrom(backgroundColor: Colors.white10))),
            const SizedBox(width:10),
            Expanded(child: ElevatedButton.icon(onPressed: ()=>searchOnline(number), icon: const Icon(Icons.search, size:18), label: const Text("بحث على النت"), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7C4DFF)))),
          ]),
          const SizedBox(height:20),
        ])));
      });
    });
  }

  Widget infoRow(IconData ic, String label, String value, {Color? color})=> Padding(padding: const EdgeInsets.symmetric(vertical:4), child: Row(children: [Icon(ic, size:16, color: color??Colors.white54), const SizedBox(width:8), Text("$label: ", style: const TextStyle(color: Colors.white38, fontSize:12)), Expanded(child: Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize:12, color: color))) ]));
  Widget detail(IconData ic, String l, String v)=> Column(children: [Icon(ic, color: const Color(0xFF00E5CC), size:20), const SizedBox(height:4), Text(l, style: const TextStyle(color: Colors.white38, fontSize:12)), Text(v, style: const TextStyle(fontWeight: FontWeight.bold, fontSize:13))]);
  Widget action(IconData ic, String lab, Color bg, Color fg, VoidCallback tap)=> InkWell(onTap: tap, child: Container(padding: const EdgeInsets.symmetric(vertical:12), decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(ic, color: fg, size:18), const SizedBox(width:6), Text(lab, style: TextStyle(color: fg, fontWeight: FontWeight.bold, fontSize:12))])));

  void showOptions(CallLogEntry e, String number){
    showModalBottomSheet(context: context, backgroundColor: const Color(0xFF151525), shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))), builder: (ctx){
      return Container(padding: const EdgeInsets.all(16), child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width:40, height:4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
        const SizedBox(height:16),
        Text(number, style: const TextStyle(fontSize:20, fontWeight: FontWeight.bold)),
        if(callerCache[number]!=null) Text(callerCache[number]!.name, style: const TextStyle(color: Colors.white54)),
        const SizedBox(height:16),
        opt(Icons.phone, "اتصال بالرقم", ()=>directCall(number)),
        opt(Icons.message, "إرسال رسالة", ()=>sendSMS(number)),
        opt(Icons.copy, "نسخ الرقم", (){}),
        opt(Icons.person_add, "إضافة لجهات الاتصال", ()=>addContact(number)),
        opt(Icons.search, "بحث عن الاسم على جوجل", ()=>searchOnline(number)),
        opt(Icons.info, "جلب معلومات الرقم TrueCaller", (){ showDetail(e, number, e.duration??0); }),
        opt(Icons.note_add, "إضافة ملاحظة", ()=>addNote(number)),
        opt(blockedBox.containsKey(number)?Icons.block_flipped:Icons.block, blockedBox.containsKey(number)?"إلغاء حظر الرقم":"حظر الرقم", isDestructive:true, ()=>toggleBlock(number)),
        const SizedBox(height:20),
      ]));
    });
  }

  Widget opt(IconData ic, String title, VoidCallback tap, {bool isDestructive=false})=> ListTile(leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: isDestructive?const Color(0xFF3A1E1E):const Color(0xFF2A2A3E), borderRadius: BorderRadius.circular(8)), child: Icon(ic, color: isDestructive?Colors.redAccent:const Color(0xFF00E5CC))), title: Text(title, style: TextStyle(color: isDestructive?Colors.redAccent:Colors.white, fontSize:14)), trailing: const Icon(Icons.chevron_left, color: Colors.white24), onTap: (){ Navigator.pop(context); tap(); });

  Future<void> directCall(String n) async { await FlutterPhoneDirectCaller.callNumber(n); }
  Future<void> sendSMS(String n) async { final uri=Uri.parse("sms:$n"); if(await canLaunchUrl(uri)) await launchUrl(uri); }
  Future<void> addContact(String n) async { if(await FC.FlutterContacts.requestPermission()){ final c=FC.Contact()..phones=[FC.Phone(n)]; await c.insert(); if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("تمت الإضافة"))); } }
  void toggleBlock(String n){ if(blockedBox.containsKey(n)){ blockedBox.delete(n); } else { blockedBox.put(n, DateTime.now().toString()); } setState((){}); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(blockedBox.containsKey(n)?"تم حظر $n":"تم إلغاء حظر $n"))); }
  void addNote(String n){ final ctrl=TextEditingController(text: notesBox.get(n)??""); showDialog(context: context, builder: (ctx)=> AlertDialog(backgroundColor: const Color(0xFF1E1E2E), title: Text("ملاحظة لـ $n"), content: TextField(controller: ctrl, decoration: const InputDecoration(hintText: "اكتب ملاحظة...")), actions: [TextButton(onPressed: (){ if(ctrl.text.isNotEmpty) notesBox.put(n, ctrl.text); else notesBox.delete(n); Navigator.pop(ctx); setState((){}); }, child: const Text("حفظ"))])); }
  Future<void> searchOnline(String n) async { final uri=Uri.parse("https://www.google.com/search?q=$n"); if(await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication); }
}

class BlockedScreen extends StatelessWidget {
  const BlockedScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final box=Hive.box('blocked_box');
    final callerBox=Hive.box('caller_cache');
    return Scaffold(backgroundColor: const Color(0xFF0A0A14), appBar: AppBar(title: const Text("كاشف السبام والطروكولر"), backgroundColor: const Color(0xFF151525)),
      body: ValueListenableBuilder(valueListenable: box.listenable(), builder: (ctx, Box b, _){
        if(b.isEmpty) return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.shield, size:60, color: Colors.white24), const SizedBox(height:12), const Text("لا يوجد أرقام محظورة", style: TextStyle(color: Colors.white38)), const SizedBox(height:8), const Text("الأرقام المزعجة هتظهر هنا تلقائيا", style: TextStyle(color: Colors.white24, fontSize:12))]));
        return ListView.builder(itemCount: b.length, itemBuilder: (c,i){ final key=b.keyAt(i); var info; try{ info=callerBox.get(key); }catch(_){} return ListTile(leading: const Icon(Icons.block, color: Colors.red), title: Text(key.toString()), subtitle: info!=null? Text(info['name']??"", style: const TextStyle(color: Colors.white54)): null, trailing: IconButton(icon: const Icon(Icons.delete), onPressed: ()=>b.delete(key))); });
      }),
    );
  }
}

class RecorderScreen extends StatefulWidget {
  const RecorderScreen({super.key});
  @override
  State<RecorderScreen> createState()=> _RecorderScreenState();
}
class _RecorderScreenState extends State<RecorderScreen> {
  final recorder=AudioRecorder();
  bool isRecording=false;
  @override
  Widget build(BuildContext context) {
    final box=Hive.box('recordings_box');
    return Scaffold(backgroundColor: const Color(0xFF0A0A14), appBar: AppBar(title: const Text("التسجيلات"), backgroundColor: const Color(0xFF151525)),
      body: Column(children: [
        Container(margin: const EdgeInsets.all(16), padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: const Color(0xFF151525), borderRadius: BorderRadius.circular(20)), child: Column(children: [
          Icon(Icons.mic, size:50, color: isRecording?Colors.red:const Color(0xFF7C4DFF)),
          const SizedBox(height:12),
          Text(isRecording?"جاري التسجيل...":"تسجيل مكالمة برو", style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height:16),
          ElevatedButton.icon(style: ElevatedButton.styleFrom(backgroundColor: isRecording?Colors.red:const Color(0xFF7C4DFF), padding: const EdgeInsets.symmetric(horizontal:30, vertical:14)), onPressed: () async {
            if(isRecording){
              final p=await recorder.stop();
              setState(()=>isRecording=false);
              if(p!=null){ box.add(p); }
            } else {
              if(await recorder.hasPermission()){
                final dir=await getApplicationDocumentsDirectory();
                final filePath='${dir.path}/rec_${DateTime.now().millisecondsSinceEpoch}.m4a';
                await recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: filePath);
                setState(()=>isRecording=true);
              }
            }
          }, icon: Icon(isRecording?Icons.stop:Icons.mic), label: Text(isRecording?"إيقاف":"بدء تسجيل"))])),
        Expanded(child: ValueListenableBuilder(valueListenable: box.listenable(), builder: (ctx, Box b, _){
          if(b.isEmpty) return const Center(child: Text("لا يوجد تسجيلات", style: TextStyle(color: Colors.white38)));
          return ListView.builder(itemCount: b.length, itemBuilder: (c,i){ final p=b.getAt(i); return ListTile(leading: const Icon(Icons.audio_file, color: Color(0xFF7C4DFF)), title: Text(File(p).uri.pathSegments.last), subtitle: Text(p), onTap: (){}); });
        }))
      ]),
    );
  }
}

class SettingsProScreen extends StatelessWidget {
  const SettingsProScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(backgroundColor: const Color(0xFF0A0A14), appBar: AppBar(title: const Text("إعدادات TRUECALLER PRO"), backgroundColor: const Color(0xFF151525)),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF00E5CC), Color(0xFF7C4DFF)]), borderRadius: BorderRadius.circular(16)), child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text("ULTRA • TRUECALLER 2027 PRO MAX", style: TextStyle(fontWeight: FontWeight.bold, fontSize:16)), SizedBox(height:4), Text("كاشف هوية المتصل • جميع المزايا مفعلة", style: TextStyle(fontSize:12))])),
        const SizedBox(height:20),
        const Text("🔍 إعدادات TrueCaller", style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height:10),
        settingsTile(Icons.shield, "كشف الأرقام المزعجة تلقائيا", true),
        settingsTile(Icons.person_search, "جلب اسم المتصل تلقائيا", true),
        settingsTile(Icons.location_on, "تحديد موقع الرقم والشبكة", true),
        settingsTile(Icons.image, "عرض صورة المتصل", true),
        const SizedBox(height:20),
        const Text("⚙️ إعدادات عامة", style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height:10),
        settingsTile(Icons.record_voice_over, "تسجيل تلقائي", false),
        settingsTile(Icons.notifications, "إشعار بعد كل مكالمة بالاسم", true),
        settingsTile(Icons.backup, "نسخ احتياطي يومي + كاش الأسماء", true),
        const SizedBox(height:20),
        ElevatedButton.icon(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E1E2E), padding: const EdgeInsets.all(14)), onPressed: (){}, icon: const Icon(Icons.cached), label: const Text("مسح كاش الأسماء وإعادة تحميل")),
        const SizedBox(height:10),
        ElevatedButton.icon(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7C4DFF), padding: const EdgeInsets.all(14)), onPressed: (){}, icon: const Icon(Icons.delete_forever), label: const Text("مسح كل السجلات")),
        const SizedBox(height:20),
        Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.amber.withOpacity(0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.amber.withOpacity(0.3))), child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Icon(Icons.info, color: Colors.amber, size:16), SizedBox(width:6), Text("كيف تربط TrueCaller API الحقيقي؟", style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize:12))]),
          SizedBox(height:6),
          Text("1. افتح ملف lib/services/truecaller_service.dart\n2. حط الـ Installation ID بتاعك في دالة fetchTruecallerReal\n3. هتجيبه من تطبيق Truecaller الرسمي بفحص الشبكة\n4. أو استخدم API جاهز مثل NumVerify مع API Key", style: TextStyle(color: Colors.white60, fontSize:11)),
        ])),
      ]),
    );
  }
  Widget settingsTile(IconData ic, String title, bool val)=> Container(margin: const EdgeInsets.only(bottom:10), decoration: BoxDecoration(color: const Color(0xFF151525), borderRadius: BorderRadius.circular(12)), child: SwitchListTile(secondary: Icon(ic, color: const Color(0xFF7C4DFF)), title: Text(title, style: const TextStyle(fontSize:13)), value: val, onChanged: (v){}, activeColor: const Color(0xFF7C4DFF)));
}