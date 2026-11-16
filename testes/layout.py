"""Checa CSS/cascata com o estilo original; não simula renderização visual."""
import sys,re,os
from pathlib import Path
if os.environ.get('CDE_CSS_QA_PATH'):sys.path.insert(0,os.environ['CDE_CSS_QA_PATH'])
import tinycss2,cssselect2
from lxml import html
base=Path(__file__).resolve().parents[1]
original=(base/'testes/pdi.fixture.css').read_text()
css=(base/'desempenho.css').read_text()
matcher=cssselect2.Matcher();errors=[];count=0
for sheet in [original,css]:
 for rule in tinycss2.parse_stylesheet(sheet,skip_comments=True,skip_whitespace=True):
  if rule.type=='error':errors.append(rule.message)
  if rule.type!='qualified-rule':continue
  selector=tinycss2.serialize(rule.prelude).strip()
  declarations=[(d.lower_name,tinycss2.serialize(d.value).strip(),d.important)for d in tinycss2.parse_declaration_list(rule.content,skip_comments=True,skip_whitespace=True)if d.type=='declaration']
  try:
   for compiled in cssselect2.compile_selector_list(selector):matcher.add_selector(compiled,declarations)
  except cssselect2.SelectorError:pass
def check_nested(rules):
 for r in rules:
  if r.type=='error':errors.append(r.message)
  elif r.type=='at-rule' and r.content:check_nested(tinycss2.parse_rule_list(r.content,skip_comments=True,skip_whitespace=True))
  elif r.type=='qualified-rule':errors.extend(d.message for d in tinycss2.parse_declaration_list(r.content,skip_comments=True,skip_whitespace=True) if d.type=='error')
check_nested(tinycss2.parse_stylesheet(css,skip_comments=True,skip_whitespace=True))
assert not errors,errors
markup='''<html><body><div class="pdi-perf-tabs"><button id="menu" class="tab-btn pdi-perf-menu active">Desempenho</button></div><section class="pdi-perf"><button id="primary">Consultar</button><button class="pdi-perf-secondary" id="secondary">Atualizar</button><button id="disabled" disabled>Salvar</button></section></body></html>'''
computed={}
for node in cssselect2.ElementWrapper.from_html_root(html.fromstring(markup)).iter_subtree():
 if not node.id:continue
 values={};ranks={}
 for spec,order,pseudo,decls in matcher.match(node):
  if pseudo:continue
  for prop,value,important in decls:
   rank=(important,spec,order)
   if prop not in ranks or rank>=ranks[prop]:ranks[prop]=rank;values[prop]=value
 computed[node.id]=values
for target in ['primary','menu']:
 assert computed[target]['background'].lower()=='#e87722',(target,computed[target])
 assert computed[target]['color'].lower()=='#202831'
assert computed['primary']['background-image']=='none'
assert computed['secondary']['background']=='#fff'
assert computed['disabled']['background']=='#edf0f3' and computed['disabled']['opacity']=='1'
assert not re.search('#(?:b44d08|923c04|8b3904)',css,re.I),'Paleta marrom remanescente'
def luminance(color):
 rgb=[int(color[i:i+2],16)/255 for i in [1,3,5]]
 c=[v/12.92 if v<=0.04045 else ((v+.055)/1.055)**2.4 for v in rgb]
 return sum(v*w for v,w in zip(c,[.2126,.7152,.0722]))
a,b=sorted([luminance('#e87722'),luminance('#202831')]);ratio=(b+.05)/(a+.05)
assert ratio>=4.5,ratio
assert '@media(max-width:480px)' in css and '@media(max-width:600px)' in css and '@media(max-width:760px)' in css
assert 'min-width:0' in css and 'repeat(2,minmax(0,1fr))' in css
print(f'Cascata com CSS original aprovada: botões laranja, estado desabilitado neutro e contraste {ratio:.2f}:1. CSS com regras para celular/tablet; sem teste visual.')
